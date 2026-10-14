import Foundation
import Darwin
import Dispatch

struct NetworkProcessKey: Hashable {
    var pid: Int32
    var uniqueID: UInt64
}
struct ProcessNetworkRate {
    var received: Double
    var sent: Double
}

/// Counter baselines are per flow, not per PID: closing a socket must not reset
/// another socket's counters or turn an old connection's lifetime bytes into a spike.
struct NetworkFlowAccumulator {
    struct Counter {
        var process: NetworkProcessKey
        var received: UInt64
        var sent: UInt64
        var time: Double
        var ready = false
    }
    private var flows: [UInt: Counter] = [:]
    private var pending: [NetworkProcessKey: (received: Double, sent: Double)] = [:]
    private(set) var overflowed = false
    mutating func observe(source: UInt, counter: Counter) {
        guard counter.time.isFinite else { return }
        var value = counter
        if let old = flows[source], old.process == counter.process,
           counter.received >= old.received, counter.sent >= old.sent {
            value.ready = true
            let previous = pending[counter.process] ?? (0, 0)
            pending[counter.process] = (previous.received + Double(counter.received - old.received), previous.sent + Double(counter.sent - old.sent))
        }
        guard flows[source] != nil || flows.count < 16_384 else { overflowed = true; return }
        flows[source] = value
    }
    mutating func remove(source: UInt) { flows.removeValue(forKey: source) }
    mutating func drain(now: Double, elapsed: Double) -> [NetworkProcessKey: ProcessNetworkRate] {
        defer { pending.removeAll(keepingCapacity: true) }
        guard !overflowed, elapsed > 0, elapsed.isFinite else { return [:] }
        var keys = Set(pending.keys)
        for value in flows.values where value.ready && now - value.time < max(10, elapsed * 3) { keys.insert(value.process) }
        return Dictionary(uniqueKeysWithValues: keys.map { key in
            let bytes = pending[key] ?? (0, 0)
            return (key, ProcessNetworkRate(received: bytes.received / elapsed, sent: bytes.sent / elapsed))
        })
    }
}

/// Experimental system framework. Only process identity and byte counters are
/// retained; addresses, names, endpoints and payloads in callbacks are discarded.
/// A single background serial queue owns flow state. Queries are asynchronous;
/// no shell process, packet capture, external connection or privileged helper.
final class ProcessNetworkSampler {
    private typealias SourceBlock = @convention(block) (UnsafeMutableRawPointer) -> Void
    private typealias DictBlock = @convention(block) (CFDictionary) -> Void
    private typealias EmptyBlock = @convention(block) () -> Void
    private typealias Create = @convention(c) (CFAllocator?, DispatchQueue, @escaping SourceBlock) -> UnsafeMutableRawPointer?
    private typealias One = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias SetDict = @convention(c) (UnsafeMutableRawPointer, @escaping DictBlock) -> Void
    private typealias SetRemoved = @convention(c) (UnsafeMutableRawPointer, @escaping EmptyBlock) -> Void
    private typealias Query = @convention(c) (UnsafeMutableRawPointer, EmptyBlock?) -> Void
    private struct API {
        var create: Create; var destroy: One; var tcp: One; var udp: One
        var counts: SetDict; var description: SetDict; var queryDescription: One
        var removed: SetRemoved; var query: Query
        static func load() -> API? {
            // Keep system code loaded for the process lifetime: framework callbacks
            // may finish after manager destruction. There is only one shared load.
            guard let library = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics", RTLD_LAZY | RTLD_LOCAL) else { return nil }
            func symbol<T>(_ name: String, _: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let create = symbol("NStatManagerCreate", Create.self), let destroy = symbol("NStatManagerDestroy", One.self),
                  let tcp = symbol("NStatManagerAddAllTCP", One.self), let udp = symbol("NStatManagerAddAllUDP", One.self),
                  let counts = symbol("NStatSourceSetCountsBlock", SetDict.self),
                  let description = symbol("NStatSourceSetDescriptionBlock", SetDict.self),
                  let queryDescription = symbol("NStatSourceQueryDescription", One.self),
                  let removed = symbol("NStatSourceSetRemovedBlock", SetRemoved.self),
                  let query = symbol("NStatManagerQueryAllSources", Query.self) else { return nil }
            return API(create: create, destroy: destroy, tcp: tcp, udp: udp, counts: counts, description: description, queryDescription: queryDescription, removed: removed, query: query)
        }
    }
    private static let api = API.load()
    private let queue = DispatchQueue(label: "TaskManager.process-network", qos: .utility)
    private var manager: UnsafeMutableRawPointer?
    private final class State { var accumulator = NetworkFlowAccumulator() }
    private let state = State()
    private var uniqueIDs: [ProcessIdentity: UInt64] = [:]
    private var checked: Set<ProcessIdentity> = []

    init() {
        guard let api = Self.api else { return }
        let state = self.state
        manager = api.create(nil, queue, { source in
            let id = UInt(bitPattern: source)
            // Querying the descriptor populates identity in subsequent count
            // callbacks. Without it the framework supplies zero PID/unique ID.
            // Descriptor content itself is deliberately not retained.
            api.description(source, { _ in })
            api.queryDescription(source)
            api.counts(source, { dictionary in
                guard let counter = Self.decode(dictionary as NSDictionary, now: ProcessInfo.processInfo.systemUptime) else { return }
                state.accumulator.observe(source: id, counter: counter)
            })
            api.removed(source, { state.accumulator.remove(source: id) })
        })
        if let manager { api.tcp(manager); api.udp(manager) }
    }
    deinit { if let manager { Self.api?.destroy(manager) } }

    static func decode(_ dictionary: NSDictionary, now: Double) -> NetworkFlowAccumulator.Counter? {
        func integer(_ key: String) -> NSNumber? {
            guard let value = dictionary[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  value.doubleValue.rounded(.towardZero) == value.doubleValue else { return nil }
            return value
        }
        guard let provider = dictionary["provider"] as? String, ["TCP", "UDP"].contains(provider),
              let pid = integer("processID"), pid.int64Value > 0, pid.int64Value <= Int64(Int32.max),
              let unique = integer("uniqueProcessID"), unique.int64Value > 0,
              let received = integer("rxBytes"), received.int64Value >= 0,
              let sent = integer("txBytes"), sent.int64Value >= 0 else { return nil }
        return .init(process: .init(pid: pid.int32Value, uniqueID: unique.uint64Value), received: received.uint64Value, sent: sent.uint64Value, time: now)
    }

    func apply(to records: inout [ProcessRecord], now: Double, elapsed: Double) -> String {
        guard let manager, let api = Self.api else { return "Experimental per-process network counters are unavailable on this macOS version." }
        let (rates, overflowed) = queue.sync { (state.accumulator.drain(now: now, elapsed: elapsed), state.accumulator.overflowed) }
        api.query(manager, nil) // Callback results are consumed on the next sampling tick.
        let live = Set(records.map(\.id))
        checked.formIntersection(live); uniqueIDs = uniqueIDs.filter { live.contains($0.key) }
        let observedPIDs = Set(rates.keys.map(\.pid))
        for index in records.indices where observedPIDs.contains(records[index].id.pid) {
            let identity = records[index].id
            if checked.insert(identity).inserted, let unique = Self.uniqueID(for: identity) { uniqueIDs[identity] = unique }
            guard let unique = uniqueIDs[identity], let rate = rates[.init(pid: identity.pid, uniqueID: unique)] else { continue }
            records[index].networkReceivedBytesPerSecond = rate.received
            records[index].networkSentBytesPerSecond = rate.sent
        }
        if overflowed { return "Experimental network flow limit reached; per-process rates are unavailable." }
        return "Experimental local TCP/UDP byte rates, including loopback. Initial samples establish flow baselines; unobserved or protected processes remain unavailable."
    }
    private static func uniqueID(for identity: ProcessIdentity) -> UInt64? {
        // XNU proc_info_private.h: flavor 17, 56 bytes, p_uniqueid at offset 16.
        // Validate start time on both sides so a reused PID never inherits traffic.
        func sameProcess() -> Bool {
            guard let info = SystemSampler.bsdInfo(identity.pid) else { return false }
            return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec == identity.startTime
        }
        guard sameProcess() else { return nil }
        var words = [UInt64](repeating: 0, count: 7)
        let size: Int32 = 56
        let read = words.withUnsafeMutableBytes { proc_pidinfo(identity.pid, 17, 0, $0.baseAddress, size) }
        guard read == size, words[2] > 0, sameProcess() else { return nil }
        return words[2]
    }
}
