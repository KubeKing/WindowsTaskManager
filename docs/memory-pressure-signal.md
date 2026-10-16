# Continuous macOS memory pressure

Research date: 2026-10-16. Read-only source and native-binary investigation; no memory-pressure workloads, product changes, packages, or privileged helper.

## Finding

**There is a usable direct kernel signal: `memorystatus_get_level`, inverted as `100 - availablePercent`. The installed Activity Monitor uses precisely this number for its memory-pressure graph height, with a separate pressure category for color.** This is an undocumented system interface, not a public supported continuous-pressure API. It can be called from native Swift through an optional dynamically resolved libSystem symbol, without a third-party dependency or helper.

Apple's user guide describes the graph in terms of free memory, swapping, wired memory, and cached files, but publishes no numerical formula or continuous sampling API. [Apple Activity Monitor guide](https://support.apple.com/en-gb/guide/activity-monitor/actmntr34865/10.14/mac/15.0).

## Direct Activity Monitor evidence

Inspected `/System/Applications/Utilities/Activity Monitor.app/Contents/MacOS/Activity Monitor` on this arm64 Mac, macOS 27.0.1 build 26A434. The bundle reports version 10.14. Binary SHA-256: `70593b6e60f57767255a1bca5d9c5da09abb9f410a2cb0405bae5843ff89fd5d`.

The following observations come from the installed Apple binary, not an inferred third-party formula. Addresses are unslid addresses in its arm64e slice:

- `0x100012da4` calls `memorystatus_get_level` with a pointer to a four-byte stack value. On success, `0x100012db4` loads 100 and `0x100012db8` subtracts the returned value. `0x100012dd0` passes the result to `setMemoryStatusLevel:`.
- `0x100012e00` separately calls `sysctlbyname("kern.memorystatus_vm_pressure_level", ...)`. `0x100012e24` passes that result to `setMemoryPressure:`. The property names are easy to confuse: `memoryStatusLevel` is the numeric height; `memoryPressure` is the category.
- `SMMemoryGraphController`'s method at `0x100014ea8` fetches `systemStatistics.memoryStatusLevel` at `0x100014eec`, converts it to a float, and supplies it unchanged to `addValue:withGradientIndex:` at `0x100014f54`. It separately maps the categorical value 4 to gradient 2, 2 to gradient 1, and other values to gradient 0.
- Its setup method at `0x1000148a4` calls `setMaxValue:` with float 100 at `0x100014910`, then `setStep:` with 3.0. The numeric graph uses a fixed 100 maximum; it does not substitute three categorical heights.

Reproduce with `otool -tvV`, `otool -ov`, `otool -v -s __TEXT __objc_stubs`, and `otool -v -s __DATA __objc_selrefs` against that binary. Resolve each Objective-C stub through its selector-reference address; the selector names above were verified this way. `otool -L` confirms that Activity Monitor links `libsysmon.dylib` and `libsystemstats.dylib`, but neither is needed for the numeric sample shown above. This finding is scoped to the inspected binary, not a guarantee about every Activity Monitor version.

## Kernel meaning and native signature

Apple declares `int memorystatus_get_level(user_addr_t level)`: the argument is a userspace address, and the return value is an error status, not the percentage. The syscall copies out the four-byte `memorystatus_level`; it does not perform a root/entitlement check. The read-only `kern.memorystatus_level` sysctl exposes the same stored variable. [Apple XNU declaration](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/kern_memorystatus.h), [syscall implementation, lines 807–820](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus.c#L807-L820).

`vm_pressure_response` computes the integer percentage as `available_pages * 100 / total_pages`, with any secluded pages subtracted from the denominator. The ordinary non-jetsam macOS path supplies `active + inactive + free + speculative` as available pages. Active memory is deliberately included: this is working-set capacity, not literal unused RAM or the application's existing Memory Used percentage. [Apple XNU calculation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_pageout.c#L4380-L4401), [available-page definitions](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_page.h#L1418-L1442).

Apple's own `memory_pressure` utility calls this syscall in `get_percent_free` and prints its result as a system-wide percentage. Mozilla independently documents and reads the same percentage, distinguishing it from the categorical pressure sysctl. [Apple utility](https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c#L117-L129), [Mozilla implementation](https://github.com/mozilla-firefox/firefox/blob/main/xpcom/base/AvailableMemoryWatcherMac.cpp#L335-L355).

In this tool sandbox, a read-only probe as uid 501 returned status 0 and percentage 48 through the libc symbol, while `sysctlbyname` for both memorystatus variables returned `EPERM`. Therefore the syscall path can work where the sysctl path is denied. The current local SDK exports `_memorystatus_get_level` in `libsystem_kernel.tbd`, but has no callable declaration in public headers. Successful execution is not a public API stability promise.

## Implementation path and limits

Resolve `memorystatus_get_level` once from libSystem (or the default dynamic-symbol scope). A Swift C function type taking `UnsafeMutablePointer<Int32>` and returning `Int32` matches the observed 64-bit pointer ABI; the Apple declaration expresses the pointer as `user_addr_t`. Accept only status 0 and an output in 0...100, then graph `Double(100 - availablePercent)` on a fixed 0...100 axis. Retain the existing native categorical pressure source for green/yellow/red semantics. Mark unavailable numeric samples as gaps; do not fabricate a Normal-height sample or substitute RAM-used percent.

The signal is OS-wide and requires no SoC/SKU lookup. The source supports an architecture-independent mechanism; only this machine/build was exercised. Runtime symbol resolution and failure handling remain necessary across Apple Silicon and future macOS versions. Public `host_statistics64` counters could approximate parts of the kernel formula, but snapshot timing, secluded/stolen memory, and kernel policy changes prevent claiming exact Activity Monitor equivalence. A public-API-only implementation should label such a curve as an estimate.

`vm.memory_pressure` is a different continuous counter: `record_memory_pressure` sums pages reclaimed from several queues in the previous pageout-stat interval. `mach_vm_pressure_monitor` also exposes pages reclaimed/wanted. Neither is the graph's bounded percentage. Compressor thresholds explain categorical transitions and hysteresis; they do not create a separate published continuous score. [Apple pageout counters](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_pageout.c#L900-L1006), [Apple pressure design](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md).
