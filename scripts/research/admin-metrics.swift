// Research-only diagnostic. Not linked into Task Manager or installed as a service.
// Uses only macOS tools/frameworks. Never saves raw trace lines, paths or app names.
import Foundation
import Darwin

struct Interval {
    var start: Double
    var end: Double
}
func coverage(_ intervals: [Interval], from start: Double, to end: Double) -> Double {
    guard start.isFinite, end.isFinite, end > start else { return 0 }
    let sorted = intervals.compactMap { interval -> Interval? in
        guard interval.start.isFinite, interval.end.isFinite, interval.end >= interval.start else { return nil }
        let clipped = Interval(start: max(start, interval.start), end: min(end, interval.end))
        return clipped.end > clipped.start ? clipped : nil
    }.sorted { $0.start < $1.start }
    var total = 0.0
    var pending: Interval?
    for interval in sorted {
        if var old = pending {
            if interval.start <= old.end {
                old.end = max(old.end, interval.end); pending = old
            } else {
                total += old.end - old.start; pending = interval
            }
        } else { pending = interval }
    }
    if let pending { total += pending.end - pending.start }
    return total
}
struct Parser {
    // The built-in fs_usage rounds request durations up to microseconds.
    // Its completed-request output cannot establish completeness at boundaries.
    let pattern = try! NSRegularExpression(pattern: #"^(\d{2}):(\d{2}):(\d{2})\.(\d{6})\s+(?:RdData|WrData|RdMeta|WrMeta|PgIn|PgOut)(?:\[[^\]]*\])?\s+.*?/dev/(disk\d+(?:s\d+)*)\s+.*?\s(\d+\.\d{6})\s+(?:W\s+)?[^\n]+\.\d+\s*$"#)
    let durations = try! NSRegularExpression(pattern: #"(?<!\S)(\d+\.\d{6})(?=\s+(?:W\s+)?[^\n]+\.\d+\s*$)"#)
    func parse(_ line: String) -> (device: String, finish: Double, duration: Double)? {
        let range = NSRange(line.startIndex..., in:line)
        guard let match = pattern.firstMatch(in: line, range: range),
              durations.numberOfMatches(in:line,range:range) == 1 else { return nil }
        func group(_ index: Int) -> String { String(line[Range(match.range(at:index), in:line)!]) }
        guard let hour = Double(group(1)), let minute = Double(group(2)), let second = Double(group(3)), let micro = Double(group(4)),
              let duration = Double(group(6)), hour < 24, minute < 60, second < 60,
              duration.isFinite, duration >= 0, duration < 86_400 else { return nil }
        return (group(5), hour * 3600 + minute * 60 + second + micro / 1e6, duration)
    }
}
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--cpu") || CommandLine.arguments.contains("--cpu-native") {
    let reference = CommandLine.arguments.contains("--cpu")
    guard !reference || geteuid() == 0 else { fputs("Administrator access is required for the Apple CPU reference.\n",stderr); exit(3) }
    let sampler = CPUFrequencySampler()
    _ = sampler.sample()
    let tool = Process(), output = Pipe()
    tool.executableURL = URL(fileURLWithPath:"/usr/bin/powermetrics")
    tool.arguments = ["--samplers","cpu_power","-i","1000","-n","5"]
    tool.standardOutput = output; tool.standardError = output
    if reference {
        do { try tool.run() } catch { fputs("Could not start Apple's CPU reference.\n",stderr); exit(4) }
    }
    var native: [[String:Double]] = []
    for _ in 0..<5 {
        Thread.sleep(forTimeInterval:1)
        let value = sampler.sample()
        var reading: [String:Double] = [:]
        reading["performance_MHz"] = value.performanceMHz
        reading["efficiency_MHz"] = value.efficiencyMHz
        native.append(reading)
    }
    // Drain while the tool exits; cpu_power emits only a small bounded report.
    let text = reference ? String(decoding:output.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self) : ""
    if reference { tool.waitUntilExit() }
    let expression = try! NSRegularExpression(pattern:#"^\s*((?:[EP]\d*-Cluster|CPU\s+\d+)\s+(?:HW active\s+)?frequency):\s*([0-9.]+)\s*MHz"#)
    let apple = text.split(separator:"\n").compactMap { line -> [String:Any]? in
        let line = String(line)
        guard let match = expression.firstMatch(in:line,range:NSRange(line.startIndex...,in:line)),
              let value = Double(line[Range(match.range(at:2),in:line)!]) else { return nil }
        return ["field":String(line[Range(match.range(at:1),in:line)!]),"MHz":value]
    }
    var frequencyMetadata: [[String:Any]] = []
    for key in ["hw.cpufrequency","hw.cpufrequency_min","hw.cpufrequency_max"] {
        var number: UInt64 = 0, size = MemoryLayout<UInt64>.size
        let status = sysctlbyname(key,&number,&size,nil,0)
        frequencyMetadata.append(["key":key,"available":status == 0,"value":status == 0 ? number : 0,"errno":status == 0 ? 0 : errno])
    }
    let report: [String:Any] = ["purpose":"CPU reference comparison; windows overlap approximately, not exactly",
        "powermetrics_exit_status":reference ? tool.terminationStatus : -1,"apple_frequency_readings":apple,
        "native_active_cluster_samples":native,"sysctl_frequency_metadata":frequencyMetadata,
        "note":"No raw Apple output, host identity or process information retained. Base frequency is not inferred from max frequency."]
    print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    exit(!reference || (tool.terminationStatus == 0 && !apple.isEmpty) ? 0 : 5)
}
if CommandLine.arguments.contains("--self-test") {
    check(coverage([.init(start:1,end:5), .init(start:3,end:7)],from:0,to:10) == 6, "overlap counted once")
    check(coverage([.init(start:3,end:7), .init(start:1,end:5)],from:0,to:10) == 6, "completion order independent")
    check(coverage([.init(start:-1,end:3), .init(start:7,end:15)],from:0,to:10) == 6, "window clipping")
    check(coverage([.init(start:1,end:7), .init(start:2,end:3)],from:0,to:10) == 6, "nested requests")
    check(coverage([.init(start:1,end:2), .init(start:2,end:3)],from:0,to:10) == 2, "adjacent requests")
    check(coverage([.init(start:1,end:2), .init(start:1,end:2)],from:0,to:10) == 1, "duplicate interval")
    check(coverage([.init(start:.nan,end:2), .init(start:3,end:2)],from:0,to:10) == 0, "invalid intervals")
    check(coverage([],from:0,to:10) == 0, "empty window")
    let line = "12:34:56.123456 RdData[AP] D=0x00000000 B=0x1000 /dev/disk3s1 /private/example 0.001234 W Example.42"
    let parsed = Parser().parse(line)
    check(parsed?.device == "disk3s1" && parsed?.duration == 0.001234, "numeric fields parsed without retaining path/name")
    check(Parser().parse("12:34:56.123456 open /private/example 0.001234 Example.42") == nil, "non-disk events excluded")
    check(Parser().parse(line.replacingOccurrences(of:"/private/example",with:"/private/ 1.000000 example")) == nil, "ambiguous text rejected")
    check(Parser().parse(line.replacingOccurrences(of:" W ",with:" "))?.duration == 0.001234, "optional wait marker")
    print("PASS: 12 diagnostic parser/interval checks; synthetic data only")
    exit(0)
}
let args = CommandLine.arguments
let seconds = args.count > 1 ? Int(args[1]) ?? 0 : 30
guard (5...60).contains(seconds) else { fputs("Usage: AdminMetricsProbe [5...60 seconds] | --self-test\n", stderr); exit(2) }
guard geteuid() == 0 else { fputs("Administrator access is required for this one-time diagnostic. No service is installed.\n", stderr); exit(3) }

func usage(_ who: Int32) -> rusage {
    var value = rusage(); getrusage(who, &value); return value
}
func cpu(_ value: rusage) -> Double {
    Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec)/1e6
}
let parser = Parser()
let process = Process(), pipe = Pipe()
process.executableURL = URL(fileURLWithPath:"/usr/bin/fs_usage")
// -e excludes only this diagnostic; avoids fs_usage's default exclusions of shells.
process.arguments = ["-w", "-f", "diskio", "-t", String(seconds), "-e", String(getpid())]
process.standardOutput = pipe; process.standardError = pipe
let beforeSelf = usage(RUSAGE_SELF), beforeChild = usage(RUSAGE_CHILDREN)
let startUptime = ProcessInfo.processInfo.systemUptime
let date = Date(), calendar = Calendar.current
let parts = calendar.dateComponents([.hour,.minute,.second,.nanosecond], from:date)
let startDay = Double(parts.hour! * 3600 + parts.minute! * 60 + parts.second!) + Double(parts.nanosecond!)/1e9
var intervals: [String:[Interval]] = [:]
var count = 0, malformed = 0, warnings = 0
var pending = Data()
let limit = 250_000
func consume(_ line: String) {
    let lower = line.lowercased()
    if ["overrun", "dropped", "ktrace_start", "must be run", "error", "failed", "lost events"].contains(where:lower.contains) { warnings += 1 }
    guard let event = parser.parse(line) else {
        if line.contains("/dev/disk") { malformed += 1 }
        return
    }
    guard count < limit else { warnings += 1; return }
    var finish = event.finish
    if finish < startDay - 43_200 { finish += 86_400 }
    if finish > startDay + 43_200 { finish -= 86_400 }
    intervals[event.device, default:[]].append(Interval(start:finish-event.duration,end:finish))
    count += 1
}
do { try process.run() } catch { fputs("Could not start the built-in disk tracing tool.\n",stderr); exit(4) }
while true {
    let data = pipe.fileHandleForReading.availableData
    if data.isEmpty { break }
    pending.append(data)
    while let newline = pending.firstIndex(of:10) {
        let line = String(decoding:pending[..<newline],as:UTF8.self)
        consume(line)
        pending.removeSubrange(...newline)
    }
    if pending.count > 65_536 { warnings += 1; pending.removeAll(keepingCapacity:true) }
}
if !pending.isEmpty { consume(String(decoding:pending,as:UTF8.self)) }
process.waitUntilExit()
let wall = ProcessInfo.processInfo.systemUptime - startUptime
let afterSelf = usage(RUSAGE_SELF), afterChild = usage(RUSAGE_CHILDREN)
let totalCPU = cpu(afterSelf)-cpu(beforeSelf)+cpu(afterChild)-cpu(beforeChild)
var devices: [[String:Any]] = []
for device in intervals.keys.sorted() {
    let span = coverage(intervals[device]!,from:startDay,to:startDay+wall)
    devices.append(["bsd_device":device,"completed_requests":intervals[device]!.count,
                    "observed_completed_request_coverage_percent":100*span/wall])
}
let report: [String:Any] = [
    "purpose":"Research-only; NOT validated disk Active time",
    "capture_exit_status":process.terminationStatus,
    "wall_seconds":wall,"trace_warnings":warnings,"unparsed_disk_lines":malformed,
    "diagnostic_cpu_seconds_including_fs_usage":totalCPU,
    "diagnostic_percent_of_one_cpu":100*totalCPU/wall,
    "diagnostic_peak_rss_bytes":afterSelf.ru_maxrss,
    "fs_usage_peak_rss_bytes":afterChild.ru_maxrss,
    "devices":devices,
    "limitations":["Only completed traced requests; requests still outstanding at stop are missing.",
                   "Initial in-flight requests and lost events cannot be fully reconciled by text output.",
                   "Durations rounded up to microseconds; wall clock changes can invalidate results.",
                   "BSD devices are not yet verified physical/APFS associations. Do not sum device percentages.",
                   "CPU/RSS describe this diagnostic plus fs_usage, not a future native helper.",
                   "No file paths, application names, process IDs, raw traces or remote requests retained."]]
let output = try JSONSerialization.data(withJSONObject:report, options:[.prettyPrinted,.sortedKeys])
print(String(decoding:output,as:UTF8.self))
exit(process.terminationStatus == 0 && warnings == 0 && malformed == 0 ? 0 : 5)
