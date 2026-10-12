import Foundation
import Darwin
import IOKit

struct StorageDevice {
    var metric: DiskMetrics
    var descendantBSDNames: Set<String>
}

/// Joins a filesystem only to its verified registry ancestor. Never adds APFS
/// volume capacities together: sibling volumes can share the same free space.
enum StorageTopology {
    static func join(devices: [StorageDevice], volumes: [DiskVolume]) -> [DiskMetrics] {
        var matched: Set<String> = []
        var result = devices.map { device in
            var metric = device.metric
            metric.volumes = volumes.filter { device.descendantBSDNames.contains($0.id) }
                .sorted { ($0.mountPath == "/" ? 0 : 1, $0.mountPath) < ($1.mountPath == "/" ? 0 : 1, $1.mountPath) }
            matched.formUnion(metric.volumes.map(\.id))
            return metric
        }
        for volume in volumes where !matched.contains(volume.id) {
            var metric = DiskMetrics(id: "/dev/" + volume.id, name: volume.name, mountPath: volume.mountPath)
            metric.bsdName = volume.id; metric.volumes = [volume]
            metric.totalBytes = volume.totalBytes; metric.freeBytes = volume.freeBytes
            result.append(metric)
        }
        return result.sorted(by: ordered)
    }
    static func ordered(_ lhs: DiskMetrics, _ rhs: DiskMetrics) -> Bool {
        let leftRank = lhs.kind == .physical ? 0 : lhs.kind == .volume ? 1 : 2
        let rightRank = rhs.kind == .physical ? 0 : rhs.kind == .volume ? 1 : 2
        return (leftRank, lhs.bsdName ?? lhs.id) < (rightRank, rhs.bsdName ?? rhs.id)
    }
}

/// Metadata/filesystem capacity is refreshed every 30 seconds; only driver
/// byte counters are read each tick. No subprocess or privileged helper.
final class StorageSampler {
    private struct Counters { var read: UInt64; var write: UInt64 }
    private var previous: [String: Counters] = [:]
    private var metadata: [String: DiskMetrics] = [:]
    private var topology: [String: StorageDevice] = [:]
    private var knownIDs: Set<String> = []
    private var lastRefresh = -Double.infinity

    func sample(now: Double, elapsed: Double) -> [DiskMetrics] {
        let refresh = now - lastRefresh > 30
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            previous.removeAll()
            return StorageTopology.join(devices: [], volumes: Self.mountedVolumes())
        }
        defer { IOObjectRelease(iterator) }
        if refresh { topology.removeAll() }
        var topologyChanged = refresh
        var current: [String: Counters] = [:]
        var liveIDs: Set<String> = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { continue }
            let id = "io:\(entryID)"
            liveIDs.insert(id)
            if refresh || !knownIDs.contains(id) {
                topologyChanged = true
                if let device = Self.device(service, id: id) { topology[id] = device }
            }
            guard let stats = Self.property(service, "Statistics") as? [String: Any],
                  let read = stats["Bytes (Read)"] as? NSNumber,
                  let write = stats["Bytes (Write)"] as? NSNumber else { continue }
            current[id] = Counters(read: read.uint64Value, write: write.uint64Value)
        }
        topologyChanged = topologyChanged || liveIDs != knownIDs
        knownIDs = liveIDs
        topology = topology.filter { liveIDs.contains($0.key) }
        if topologyChanged {
            let joined = StorageTopology.join(devices: Array(topology.values), volumes: Self.mountedVolumes())
            metadata = Dictionary(joined.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            lastRefresh = now
        }
        let result = metadata.values.map { stored in
            var metric = stored
            if let value = current[metric.id] {
                metric.readBytesPerSecond = RateMath.rate(current: value.read, previous: previous[metric.id]?.read, elapsed: elapsed)
                metric.writeBytesPerSecond = RateMath.rate(current: value.write, previous: previous[metric.id]?.write, elapsed: elapsed)
            }
            return metric
        }.sorted(by: StorageTopology.ordered)
        previous = current
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private static func device(_ service: io_service_t, id: String) -> StorageDevice? {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }
        while true {
            let media = IOIteratorNext(children)
            guard media != 0 else { return nil }
            defer { IOObjectRelease(media) }
            guard IOObjectConformsTo(media, "IOMedia") != 0,
                  property(media, "Whole") as? Bool == true,
                  let bsd = property(media, "BSD Name") as? String,
                  let capacity = property(media, "Size") as? NSNumber else { continue }
            var parent: io_registry_entry_t = 0
            let parentOK = IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS
            defer { if parentOK { IOObjectRelease(parent) } }
            let protocolInfo = parentOK ? property(parent, "Protocol Characteristics") as? [String: Any] : nil
            let characteristics = parentOK ? property(parent, "Device Characteristics") as? [String: Any] : nil
            let connection = protocolInfo?["Physical Interconnect"] as? String
            let location = protocolInfo?["Physical Interconnect Location"] as? String
            let image = connection == "Virtual Interface" || location == "File"
            let medium = characteristics?["Medium Type"] as? String
            let name = image ? "Disk image" : location == "Internal" ? (medium == "Solid State" ? "Internal SSD" : "Internal disk") : location == "External" ? "External disk" : "Disk"
            var metric = DiskMetrics(id: id, name: name, mountPath: "Whole device")
            metric.kind = image ? .image : .physical
            metric.preferenceID = RegistryIdentity.path(of: service)
            metric.bsdName = bsd
            metric.model = characteristics?["Product Name"] as? String
            metric.connection = connection
            metric.totalBytes = capacity.uint64Value
            var names: Set<String> = [bsd]
            var descendants: io_iterator_t = 0
            if IORegistryEntryCreateIterator(media, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &descendants) == KERN_SUCCESS {
                defer { IOObjectRelease(descendants) }
                while true {
                    let entry = IOIteratorNext(descendants)
                    guard entry != 0 else { break }
                    if let name = property(entry, "BSD Name") as? String { names.insert(name) }
                    IOObjectRelease(entry)
                }
            }
            return StorageDevice(metric: metric, descendantBSDNames: names)
        }
    }
    private static func mountedVolumes() -> [DiskVolume] {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard let mounts, count > 0 else { return [] }
        var volumes: [DiskVolume] = []
        for index in 0..<Int(count) {
            var mount = mounts[index]
            let path = withUnsafePointer(to: &mount.f_mntonname) { p in p.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            let device = withUnsafePointer(to: &mount.f_mntfromname) { p in p.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            guard device.hasPrefix("/dev/"), path == "/" || path.hasPrefix("/Volumes/") else { continue }
            let url = URL(fileURLWithPath: path)
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? (path == "/" ? "Startup volume" : url.lastPathComponent)
            volumes.append(DiskVolume(id: String(device.dropFirst(5)), name: name, mountPath: path,
                                      totalBytes: mount.f_blocks * UInt64(mount.f_bsize), freeBytes: mount.f_bavail * UInt64(mount.f_bsize)))
        }
        return volumes
    }
}
