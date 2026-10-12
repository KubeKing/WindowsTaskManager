import Foundation

public struct ProcessIdentity: Hashable, Codable, Sendable {
    public var pid: Int32
    /// Process creation time in microseconds since the Unix epoch.
    public var startTime: UInt64
    public init(pid: Int32, startTime: UInt64) { self.pid = pid; self.startTime = startTime }
}

public struct ProcessRecord: Identifiable, Hashable, Sendable {
    public var id: ProcessIdentity
    public var name: String
    public var executablePath: String? = nil
    public var applicationPath: String? = nil
    public var parentPID: Int32 = 0
    public var uid: UInt32 = 0
    public var user: String = ""
    public var status: String? = nil
    public var cpuPercent: Double? = nil
    public var memoryBytes: UInt64? = nil
    public var threadCount: Int? = nil
    public var diskReadBytes: UInt64? = nil
    public var diskWriteBytes: UInt64? = nil
    public var readBytesPerSecond: Double? = nil
    public var writeBytesPerSecond: Double? = nil
    public var totalCPUSeconds: Double? = nil
    public var isApplication: Bool { applicationPath != nil }
    public init(id: ProcessIdentity, name: String) { self.id = id; self.name = name }
}

public struct MemoryMetrics: Sendable {
    public var usageAvailable: Bool = false
    public var swapAvailable: Bool = false
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var availableBytes: UInt64 = 0
    public var compressedBytes: UInt64 = 0
    public var swapUsedBytes: UInt64 = 0
    public var wiredBytes: UInt64 = 0
    /// File-backed pages reported by Mach, including reclaimable cached files.
    public var cachedBytes: UInt64? = nil
    /// Completely free pages; excludes speculative pages.
    public var freeBytes: UInt64? = nil
    public var pressure: String = "Unknown"
    public var usedPercent: Double? { usageAvailable && totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : nil }
    public init() {}
}

public struct NetworkMetrics: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var address: String? = nil
    public var receivedBytes: UInt64 = 0
    public var sentBytes: UInt64 = 0
    public var receiveBytesPerSecond: Double? = nil
    public var sendBytesPerSecond: Double? = nil
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct DiskMetrics: Identifiable, Sendable {
    public var id: String
    public var preferenceID: String? = nil
    public var name: String
    public var mountPath: String
    public var totalBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var readBytesPerSecond: Double? = nil
    public var writeBytesPerSecond: Double? = nil
    public init(id: String, name: String, mountPath: String) { self.id = id; self.name = name; self.mountPath = mountPath }
}

public struct GPUMetrics: Identifiable, Sendable {
    public var id: String
    public var preferenceID: String? = nil
    public var name: String
    public var utilization: Double? = nil
    public var rendererUtilization: Double? = nil
    public var tilerUtilization: Double? = nil
    public var memoryInUseBytes: UInt64? = nil
    public var memoryAllocatedBytes: UInt64? = nil
    public var coreCount: Int? = nil
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct SystemSnapshot: Sendable {
    public var timestamp: Date = Date()
    public var monotonicTime: Double = 0
    public var processes: [ProcessRecord] = []
    public var cpuUsage: Double? = nil
    public var logicalCPUUsage: [Double] = []
    public var cpuKernelUsage: Double? = nil
    public var logicalKernelUsage: [Double] = []
    public var memory: MemoryMetrics = .init()
    public var networks: [NetworkMetrics] = []
    public var disks: [DiskMetrics] = []
    public var gpus: [GPUMetrics] = []
    public var uptime: Double = 0
    public var cpuName: String = "Apple silicon"
    public var logicalCPUCount: Int = ProcessInfo.processInfo.activeProcessorCount
    public var loadAverage: [Double] = []
    public var collectionDuration: Double = 0
    public var warnings: [String] = []
    public init() {}
}

public struct HistoryPoint: Identifiable, Sendable {
    public var id: Date { timestamp }
    public var timestamp: Date
    public var cpu: Double?
    public var memory: Double?
    public var totalMemoryBytes: UInt64?
    public var systemUsedMemoryBytes: UInt64?
    public var networkReceived: Double?
    public var networkSent: Double?
    public var logicalCPU: [Double]
    public var kernelCPU: Double?
    public var logicalKernel: [Double]
    public var networkByID: [String: NetworkMetrics]
    public var diskByID: [String: DiskMetrics]
    public var gpuByID: [String: GPUMetrics]
    public var diskRead: Double?
    public var diskWrite: Double?
    public init(snapshot: SystemSnapshot) {
        timestamp = snapshot.timestamp; cpu = snapshot.cpuUsage; memory = snapshot.memory.usedPercent
        totalMemoryBytes = snapshot.memory.totalBytes > 0 ? snapshot.memory.totalBytes : nil
        systemUsedMemoryBytes = snapshot.memory.usageAvailable ? snapshot.memory.usedBytes : nil
        logicalCPU = snapshot.logicalCPUUsage
        kernelCPU = snapshot.cpuKernelUsage
        logicalKernel = snapshot.logicalKernelUsage
        networkByID = Dictionary(snapshot.networks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        diskByID = Dictionary(snapshot.disks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        gpuByID = Dictionary(snapshot.gpus.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let devices = snapshot.disks.filter { $0.totalBytes == 0 }
        let reads = devices.compactMap(\.readBytesPerSecond)
        let writes = devices.compactMap(\.writeBytesPerSecond)
        let processReads = snapshot.processes.compactMap(\.readBytesPerSecond)
        let processWrites = snapshot.processes.compactMap(\.writeBytesPerSecond)
        diskRead = reads.isEmpty ? (processReads.isEmpty ? nil : processReads.reduce(0, +)) : reads.reduce(0, +)
        diskWrite = writes.isEmpty ? (processWrites.isEmpty ? nil : processWrites.reduce(0, +)) : writes.reduce(0, +)
        let receive = snapshot.networks.compactMap(\.receiveBytesPerSecond)
        let send = snapshot.networks.compactMap(\.sendBytesPerSecond)
        networkReceived = receive.isEmpty ? nil : receive.reduce(0, +)
        networkSent = send.isEmpty ? nil : send.reduce(0, +)
    }
}
