import Darwin

enum MemoryPressureMath {
    static func percent(availablePercent: Int32) -> Double? {
        guard (0...100).contains(availablePercent) else { return nil }
        return Double(100 - availablePercent)
    }
}

/// Activity Monitor reads this kernel level separately from the pressure color.
/// Resolve the undocumented system symbol optionally so unsupported OS versions
/// yield a missing reading rather than an invented estimate or a launch failure.
final class MemoryPressureSampler {
    private typealias GetLevel = @convention(c) (UnsafeMutablePointer<Int32>) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let getLevel: GetLevel?

    init() {
        library = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_LOCAL)
        if let library, let symbol = dlsym(library, "memorystatus_get_level") {
            getLevel = unsafeBitCast(symbol, to: GetLevel.self)
        } else {
            getLevel = nil
        }
    }

    deinit { if let library { dlclose(library) } }

    func sample() -> Double? {
        var availablePercent: Int32 = -1
        guard let getLevel, getLevel(&availablePercent) == 0 else { return nil }
        return MemoryPressureMath.percent(availablePercent: availablePercent)
    }
}
