import Foundation
import Darwin
import IOKit
import SystemConfiguration

/// Collect on one serial queue. No shell commands, network requests, or privileged helpers.
public final class SystemSampler {
    private struct ProcessCounters { var cpu: UInt64?; var read: UInt64?; var write: UInt64? }
    private struct Pair { var read: UInt64; var write: UInt64 }
    private var previousTime: Double?
    private var previousProcesses: [ProcessIdentity: ProcessCounters] = [:]
    private var metadata: [ProcessIdentity: (path: String?, application: String?, name: String)] = [:]
    private var users: [UInt32: String] = [:]
    private var previousTicks: [[UInt64]] = []
    private var previousNetworks: [String: Pair] = [:]
    private var previousDiskDevices: [String: Pair] = [:]
    private var diskCache: [DiskMetrics] = []
    private var lastDiskRefresh = -Double.infinity
    private let timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return value
    }()
    private let gpuSampler = GPUSampler()
    private let processorCount = ProcessInfo.processInfo.activeProcessorCount
    private let processorName: String
    private var interfaceNames: [String: String] = [:]
    private var lastInterfaceRefresh = -Double.infinity
    private let pressureState = PressureState()
    private var pressureSource: DispatchSourceMemoryPressure?

    private final class PressureState: @unchecked Sendable {
        private let lock = NSLock()
        private var value = "Unknown"
        func set(_ value: String) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
    }

    public init() {
        processorName = Self.stringSysctl("machdep.cpu.brand_string") ?? "Apple silicon"
        // Public kernel pressure notifications remain useful when the pressure sysctl is denied.
        // Keep the initial state unknown until a real event arrives.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: DispatchQueue(label: "TaskManager.memoryPressure"))
        let state = pressureState
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            state.set(event.contains(.critical) ? "Critical" : event.contains(.warning) ? "Warning" : "Normal")
        }
        pressureSource = source
        source.activate()
    }
    deinit { pressureSource?.cancel() }

    public static func identity(pid: Int32) -> ProcessIdentity? {
        guard let info = bsdInfo(pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    public func sample() -> SystemSnapshot {
        let started = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { started - $0 } ?? 0
        var result = SystemSnapshot()
        result.timestamp = Date()
        result.monotonicTime = started
        result.uptime = started
        result.logicalCPUCount = processorCount
        result.cpuName = processorName
        result.processes = processes(elapsed: elapsed)
        let cpu = cpuMetrics()
        result.cpuUsage = cpu.total
        result.logicalCPUUsage = cpu.logical
        result.cpuKernelUsage = cpu.kernel
        result.logicalKernelUsage = cpu.logicalKernel
        result.memory = memoryMetrics()
        result.networks = networkMetrics(elapsed: elapsed)
        result.disks = diskMetrics(now: started, elapsed: elapsed)
        result.gpus = gpuSampler.sample()
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 { result.loadAverage = load }
        if result.processes.contains(where: { $0.memoryBytes == nil || $0.totalCPUSeconds == nil }) {
            result.warnings.append("macOS restricts some process counters. Unavailable values are shown as —.")
        }
        previousTime = started
        result.collectionDuration = ProcessInfo.processInfo.systemUptime - started
        return result
    }

    static func statusLabel(_ value: UInt32) -> String? {
        switch Int32(bitPattern: value) {
        case SIDL: return "Idle"
        case SRUN: return "Running"
        case SSLEEP: return "Sleeping"
        case SSTOP: return "Stopped"
        case SZOMB: return "Zombie"
        default: return nil
        }
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private func processes(elapsed: Double) -> [ProcessRecord] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { previousProcesses.removeAll(); return [] }
        var pids = [Int32](repeating: 0, count: Int(estimated) + 256)
        let bytes = Int32(pids.count * MemoryLayout<Int32>.stride)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, bytes) }
        guard count > 0 else { previousProcesses.removeAll(); return [] }
        var records: [ProcessRecord] = []
        records.reserveCapacity(Int(count))
        var counters: [ProcessIdentity: ProcessCounters] = [:]
        var liveMetadata: [ProcessIdentity: (path: String?, application: String?, name: String)] = [:]
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            guard let bsd = Self.bsdInfo(pid) else { continue }
            let id = ProcessIdentity(pid: pid, startTime: bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec)
            let cached = metadata[id] ?? processMetadata(pid: pid, bsd: bsd)
            liveMetadata[id] = cached
            var record = ProcessRecord(id: id, name: cached.name)
            record.executablePath = cached.path
            record.applicationPath = cached.application
            record.parentPID = Int32(bsd.pbi_ppid)
            record.uid = bsd.pbi_uid
            record.status = Self.statusLabel(bsd.pbi_status)
            if users[bsd.pbi_uid] == nil {
                users[bsd.pbi_uid] = getpwuid(bsd.pbi_uid).map { String(cString: $0.pointee.pw_name) } ?? String(bsd.pbi_uid)
            }
            record.user = users[bsd.pbi_uid] ?? String(bsd.pbi_uid)
            var task = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            var cpu: UInt64?
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size {
                record.memoryBytes = task.pti_resident_size
                record.threadCount = Int(task.pti_threadnum)
                cpu = RateMath.nanoseconds(ticks: task.pti_total_user &+ task.pti_total_system, numerator: timebase.numer, denominator: timebase.denom)
            }
            var usage = rusage_info_v2()
            let usageOK = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0 }
            }
            if usageOK {
                record.memoryBytes = usage.ri_phys_footprint
                cpu = RateMath.nanoseconds(ticks: usage.ri_user_time &+ usage.ri_system_time, numerator: timebase.numer, denominator: timebase.denom)
                record.diskReadBytes = usage.ri_diskio_bytesread
                record.diskWriteBytes = usage.ri_diskio_byteswritten
                record.readBytesPerSecond = RateMath.rate(current: usage.ri_diskio_bytesread, previous: previousProcesses[id]?.read, elapsed: elapsed)
                record.writeBytesPerSecond = RateMath.rate(current: usage.ri_diskio_byteswritten, previous: previousProcesses[id]?.write, elapsed: elapsed)
            }
            if let cpu {
                record.totalCPUSeconds = Double(cpu) / 1_000_000_000
                record.cpuPercent = RateMath.cpuPercent(current: cpu, previous: previousProcesses[id]?.cpu, elapsed: elapsed, logicalCPUs: processorCount)
            }
            counters[id] = ProcessCounters(cpu: cpu, read: record.diskReadBytes, write: record.diskWriteBytes)
            records.append(record)
        }
        previousProcesses = counters
        metadata = liveMetadata
        return records
    }

    private func processMetadata(pid: Int32, bsd: proc_bsdinfo) -> (path: String?, application: String?, name: String) {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        let path = length > 0 ? String(cString: buffer) : nil
        let application: String?
        if let path, let range = path.range(of: ".app/") { application = String(path[..<range.lowerBound]) + ".app" }
        else { application = nil }
        let rawName = withUnsafeBytes(of: bsd.pbi_name) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? (rawName.isEmpty ? "Process \(pid)" : rawName)
        return (path, application, name)
    }

    private func cpuMetrics() -> (total: Double?, logical: [Double], kernel: Double?, logicalKernel: [Double]) {
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &count) == KERN_SUCCESS, let info else { previousTicks.removeAll(); return (nil, [], nil, []) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)) }
        var ticks: [[UInt64]] = []
        var logical: [Double] = []
        var logicalKernel: [Double] = []
        var kernelTotal: UInt64 = 0
        var busyTotal: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let row = (0..<Int(CPU_STATE_MAX)).map { UInt64(UInt32(bitPattern: info[cpu * Int(CPU_STATE_MAX) + $0])) }
            ticks.append(row)
            guard cpu < previousTicks.count else { continue }
            let old = previousTicks[cpu]
            // host ticks are wrapping UInt32 counters; modular subtraction preserves wrap.
            let delta = zip(row, old).map { UInt64(UInt32(truncatingIfNeeded: $0 &- $1)) }
            let sum = delta.reduce(0, +)
            let busy = sum - delta[Int(CPU_STATE_IDLE)]
            logical.append(sum > 0 ? Double(busy) / Double(sum) * 100 : 0)
            let kernel = delta[Int(CPU_STATE_SYSTEM)]
            logicalKernel.append(sum > 0 ? Double(kernel) / Double(sum) * 100 : 0)
            kernelTotal += kernel
            busyTotal += busy
            total += sum
        }
        previousTicks = ticks
        return (logical.isEmpty ? nil : (total > 0 ? Double(busyTotal) / Double(total) * 100 : 0), logical,
                logical.isEmpty ? nil : (total > 0 ? Double(kernelTotal) / Double(total) * 100 : 0), logicalKernel)
    }

    private func memoryMetrics() -> MemoryMetrics {
        var result = MemoryMetrics()
        result.totalBytes = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) == KERN_SUCCESS }
        }
        if ok {
            result.usageAvailable = true
            let page = UInt64(vm_kernel_page_size)
            result.wiredBytes = UInt64(stats.wire_count) * page
            result.cachedBytes = UInt64(stats.external_page_count) * page
            result.freeBytes = UInt64(stats.free_count) * page
            result.compressedBytes = UInt64(stats.compressor_page_count) * page
            // Match Activity Monitor's app + wired + compressed memory, excluding reclaimable file cache.
            let occupied = (UInt64(stats.internal_page_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
            let purgeable = UInt64(stats.purgeable_count) * page
            result.usedBytes = min(result.totalBytes, occupied > purgeable ? occupied - purgeable : 0)
            result.availableBytes = result.totalBytes - result.usedBytes
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { result.swapUsedBytes = swap.xsu_used; result.swapAvailable = true }
        result.pressure = pressureState.get()
        var pressure: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0 {
            switch pressure { case 1: result.pressure = "Normal"; case 2: result.pressure = "Warning"; case 4: result.pressure = "Critical"; default: break }
        }
        return result
    }

    private func networkMetrics(elapsed: Double) -> [NetworkMetrics] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastInterfaceRefresh > 30 {
            if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
                interfaceNames = Dictionary(interfaces.compactMap { interface in
                    guard let id = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
                    let name = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? id
                    return (id, name)
                }, uniquingKeysWith: { first, _ in first })
            }
            lastInterfaceRefresh = now
        }
        var addresses: [String: String] = [:]
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0 {
            defer { freeifaddrs(interfaces) }
            var item = interfaces
            while let current = item {
                let value = current.pointee
                let name = String(cString: value.ifa_name)
                if let address = value.ifa_addr, address.pointee.sa_family == AF_INET {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { addresses[name] = String(cString: host) }
                }
                item = value.ifa_next
            }
        }
        // NET_RT_IFLIST2 exposes 64-bit interface counters. Restrict to physical en interfaces
        // to avoid counting each packet again on loopback, VPNs, bridges, and AWDL.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { previousNetworks.removeAll(); return [] }
        var data = [UInt8](repeating: 0, count: size)
        let ok = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) == 0 }
        guard ok, size <= data.count else { previousNetworks.removeAll(); return [] }
        var result: [NetworkMetrics] = []
        var currentCounters: [String: Pair] = [:]
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0, offset + length <= size else { break }
                defer { offset += length }
                guard header.ifm_type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size else { continue }
                let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(info.ifm_index), &name) != nil else { continue }
                let id = String(cString: name)
                guard id.hasPrefix("en"), info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_LOOPBACK == 0 else { continue }
                var metric = NetworkMetrics(id: id, name: interfaceNames[id] ?? id)
                metric.address = addresses[id]
                metric.receivedBytes = info.ifm_data.ifi_ibytes
                metric.sentBytes = info.ifm_data.ifi_obytes
                metric.receiveBytesPerSecond = RateMath.rate(current: metric.receivedBytes, previous: previousNetworks[id]?.read, elapsed: elapsed)
                metric.sendBytesPerSecond = RateMath.rate(current: metric.sentBytes, previous: previousNetworks[id]?.write, elapsed: elapsed)
                currentCounters[id] = Pair(read: metric.receivedBytes, write: metric.sentBytes)
                result.append(metric)
            }
        }
        previousNetworks = currentCounters
        return result.sorted { $0.id < $1.id }
    }

    private func diskMetrics(now: Double, elapsed: Double) -> [DiskMetrics] {
        // Capacity changes slowly; avoid querying mounted filesystems every tick.
        if now - lastDiskRefresh > 30 {
            var mounts: UnsafeMutablePointer<statfs>?
            let count = getmntinfo(&mounts, MNT_NOWAIT)
            var disks: [DiskMetrics] = []
            if let mounts, count > 0 {
                for index in 0..<Int(count) {
                    var mount = mounts[index]
                    let path = withUnsafePointer(to: &mount.f_mntonname) { pointer in
                        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                    }
                    let device = withUnsafePointer(to: &mount.f_mntfromname) { pointer in
                        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                    }
                    guard device.hasPrefix("/dev/"), path == "/" || path.hasPrefix("/Volumes/") else { continue }
                    var disk = DiskMetrics(id: device, name: path == "/" ? "Macintosh HD" : URL(fileURLWithPath: path).lastPathComponent, mountPath: path)
                    disk.totalBytes = mount.f_blocks * UInt64(mount.f_bsize)
                    disk.freeBytes = mount.f_bavail * UInt64(mount.f_bsize)
                    disks.append(disk)
                }
            }
            diskCache = disks
            lastDiskRefresh = now
        }
        // Public IOBlockStorageDriver counters are physical-device totals, not APFS volume I/O.
        // Show them as distinct devices instead of duplicating the same rate on each volume.
        var iterator: io_iterator_t = 0
        var devices: [DiskMetrics] = []
        var counters: [String: Pair] = [:]
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                var entryID: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
                      let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                      let read = stats["Bytes (Read)"] as? NSNumber,
                      let write = stats["Bytes (Write)"] as? NSNumber else { continue }
                let id = "io:\(entryID)"
                let pair = Pair(read: read.uint64Value, write: write.uint64Value)
                counters[id] = pair
                var metric = DiskMetrics(id: id, name: "Physical disk \(devices.count + 1)", mountPath: "Device I/O · all volumes")
                metric.readBytesPerSecond = RateMath.rate(current: pair.read, previous: previousDiskDevices[id]?.read, elapsed: elapsed)
                metric.writeBytesPerSecond = RateMath.rate(current: pair.write, previous: previousDiskDevices[id]?.write, elapsed: elapsed)
                devices.append(metric)
            }
        }
        previousDiskDevices = counters
        return diskCache + devices
    }

    private static func stringSysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}
