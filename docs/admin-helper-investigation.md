# Optional administrator helper investigation

Status: research, 2026-10-12. No helper is installed or included in Task Manager. Active time is still unavailable. The current app and v1 release behavior are unchanged by this investigation.

## Finding

A native administrator helper is a credible route to measuring **OS-observed outstanding disk read/write time**, but an accurate physical-device result and lightweight overhead have not yet been demonstrated on the development M5. Administrator access permits tracing; it does not itself guarantee complete events, correct APFS attribution, or Windows-equivalent semantics. Do not ship a percentage simply because it fits between 0 and 100.

Apple's [fs_usage implementation](https://github.com/apple-oss-distributions/system_cmds/blob/main/fs_usage/fs_usage.c) subscribes to the filesystem disk-I/O event subclass, pairs starts/completions by request token and retains the starting device. Completions can occur on another thread, so thread IDs are not request identities. Apple [XNU's buffer completion code](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_bio.c) emits these completion events. [Kernel tracing ownership](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_ktrace.c) requires superuser access on production configurations and can return EBUSY when another foreground tracing tool owns the facility.

For a complete, correctly attributed event stream, active percentage is the union of intervals with at least one outstanding request, divided by elapsed monotonic time. Two concurrent 10 ms requests occupying the same 10 ms contribute 10 ms, not 20 ms. This avoids the double-counting in cumulative per-request timings. It measures OS request activity, including applicable queue/wait time, rather than physical flash-cell work or maximum-throughput percentage.

## Accuracy gates before app integration

- Verify start/completion argument meanings and event ordering on the running macOS version; resolve private system APIs optionally and reject unsupported formats.
- Verify event device IDs against BSD major/minor IDs and the existing IORegistry topology. APFS volumes, synthesized containers, physical stores and disk images must remain distinct. Select one accounting layer per physical device; do not sum layered representations of the same I/O.
- Compare traced read/write counts and bytes against driver deltas during known uncached workloads. Counts can differ through request splitting/merging, so explain each difference rather than treating equality as sufficient proof.
- Test idle, sequential/random I/O, overlapping requests, workloads spanning sample boundaries, external drives, errors, cancellation and sleep/wake. Test flush/TRIM coverage separately: read/write tracing alone may not cover all operations relevant to a Windows-style active metric.
- Preserve outstanding requests across samples; integrate transitions on a monotonic timeline and split intervals at window boundaries. Never calculate only requests completed in each window.
- Startup may already have outstanding requests. Suppressing one warm-up interval is not proof of a clean baseline. Establish a validated initial state or expose incomplete coverage until it can be reconciled. Incomplete starts/ends, duplicate tokens, unexpected ordering, trace loss and bounded-state overflow must invalidate affected readings. A quiet stream is not automatically a measured 0%.
- Detect trace ownership conflicts and yield when unavailable. Do not seize ownership from Instruments or other tools. Dropped events must produce unavailable values, not stale percentages.

## Lightweight, offline implementation candidate

Use one small bundled native daemon registered on demand through [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), subject to macOS approval. Keep the UI app unprivileged. Communicate via local XPC with an authenticated app identity and a narrow fixed telemetry protocol. The helper should not accept arbitrary commands, executable paths, filenames or an unrestricted registry-query interface. No sockets, HTTP client, third-party packages, persistent trace log or automatic launch at login are needed.

Subscribe only to required disk event IDs and loss/ordering metadata. Disable path resolution, executable-name lookups, stack capture, symbolication and full-system syscall tracing. Retain bounded request tokens/device IDs/timestamps; publish aggregates at the app's existing sampling interval. Prefer O(1) request lookup and a running outstanding count per device over storing completed interval history. Stop tracing when no connected client requests disk telemetry, and exit after a short idle timeout. Trace loss or a state-limit hit should fail closed.

Apple's fs_usage is suitable for an initial compatibility/overhead diagnostic, not the shipping reader: its implementation registers broader callbacks, formats text and resolves names/paths. The proposed native helper should avoid that work. No CPU/RAM saving is claimed until measured. Candidate acceptance budgets are <1% of one CPU core during idle/light activity and <20 MiB helper physical footprint, with a bounded state/buffer budget and separate measurements under heavy I/O. These are targets, not results; measure total UI + helper + kernel tracing cost, not just the helper's loop. RSS alone is not physical footprint.

The current app uses an ad-hoc signature; no valid distribution-signing identity was found in the local identity check. A public root helper needs a durable code-signing/client-authentication and update plan. Bundle identifiers or executable paths alone are insufficient authentication. Do not install a development daemon or weaken system security as a shortcut.

## Other telemetry: what administrator access changes

| Reading | Expected benefit of a helper | Limit / recommendation |
| --- | --- | --- |
| Disk active time | Potential new measured request-busy percentage if the accuracy gates pass. | Not implemented or validated yet; root alone is insufficient. |
| Disk queue depth and latency distribution | A complete request stream can provide outstanding counts and request-latency percentiles. | Same coverage, startup and physical-device attribution gates as active time. Existing mean completed-I/O response time already works without root. |
| Live P/E CPU speed | Allows comparison with Apple's built-in powermetrics and may expose additional supported reference fields. | Current native IOReport reading already measures active-time cluster frequency without root. Privilege does not inherently improve its resolution or accuracy; compare matched sampling windows and definitions first. |
| CPU base speed | No established improvement on this M5. | The app reads hw.cpufrequency if provided. Administrator access does not create missing nominal-frequency metadata. Apple does not list a GHz base clock in the M5 technical specifications. Do not relabel minimum/maximum DVFS bins as base frequency. |
| P/E supported frequency range | Usually no helper needed: available voltage/frequency tables can support a separately labelled experimental range. | Firmware-listed maximum is not a guaranteed sustained speed, and neither endpoint is a Windows nominal base clock. Validate table-to-cluster mapping. |
| CPU utilization, system RAM, filesystem capacity, device byte rates | No expected numerical accuracy gain for the existing accessible counters. | Preserve current unprivileged paths. More privilege is not a better denominator or more frequent sampling. |
| Protected process telemetry | May improve coverage for certain inaccessible processes and counters. | Root does not bypass every task-access, hardened-runtime or privacy restriction; verify field by field. PID/process-identity checks remain necessary. |
| Per-process GPU time / Mac energy impact | Built-in powermetrics advertises process GPU and energy fields that could be investigated. | Compatibility and attribution need live verification. Mac energy impact is a distinct relative score; hardware power estimates are not exact measurements or the Windows Power usage/trend model. |
| GPU/ANE power, frequency, thermal data | More reference/diagnostic options may be available on supported hardware. | Some IOReport values are already accessible without root. Prefer unprivileged access when equivalent; don't add a helper for its own sake. |
| GPU Video Decode/Encode/Copy utilization | No established benefit. | No verified separate busy counter was found. Administrator access does not manufacture an absent engine counter; energy/bandwidth are not substitutes. |

Local powermetrics help lists cpu_power, gpu_power, ane_power, disk and task samplers, per-process GPU time and energy impact. It explicitly describes power as estimated. These are available *capabilities*, not proof that every field works on this hardware. Apple [M5 technical specifications](https://www.apple.com/macbook-pro/specs/) describe core counts/types and media engines without a CPU base-clock specification.

## Prepared one-time diagnostic

`scripts/research/admin-metrics.swift` is a research executable, not an app target or service. It uses Foundation/Darwin and the existing CPUFrequencySampler source; no package is added. Build it from the repository root:

```sh
mkdir -p build/helper-research
cp scripts/research/admin-metrics.swift build/helper-research/main.swift
swiftc -O Sources/TaskManagerCore/CPUFrequencySampler.swift build/helper-research/main.swift -o build/AdminMetricsProbe
./build/AdminMetricsProbe --self-test
```

Twelve synthetic checks passed: overlapping/nested/adjacent/duplicate intervals, completion ordering, clipping, invalid/empty intervals, numeric disk parsing, exclusion of non-disk events, optional wait markers and rejection of ambiguous duration text. The unprivileged diagnostic correctly refuses live tracing. Native tracing-library symbols were inspected without enabling a session; the library and required range/loss/start/stop functions are present. The subclass convenience name is not exported and must not be treated as a required symbol.

Live validation needs an administrator's password entered directly in Terminal; noninteractive sudo returned “a password is required.” No password is requested, stored or handled by the diagnostic. Run these separately from the project root:

```sh
sudo ./build/AdminMetricsProbe 30
sudo ./build/AdminMetricsProbe --cpu
```

The first captures a bounded disk sample through built-in fs_usage and reports numeric per-BSD-device completed-request interval coverage plus diagnostic CPU/RSS. It never saves raw trace lines or prints paths/app names. Its output deliberately says **NOT validated disk Active time**: text completion output omits still-outstanding requests, startup state is incomplete, durations are rounded to microseconds, and physical/APFS attribution is not established. Trace warnings, format failures or the event cap fail the diagnostic. Do not wire these percentages into the UI.

The optional unprivileged `./build/AdminMetricsProbe --cpu-native` mode was also run: all five samples produced P/E frequencies (approximately P 3.34–3.61 GHz, E 1.78–2.20 GHz). All three hw.cpufrequency/min/max lookups returned ENOENT rather than a permission error. These observations confirm existing access and absent metadata on this Mac; they do not validate frequency accuracy against Apple’s reference.

The second takes five approximate one-second native P/E frequency samples while powermetrics runs its cpu_power sampler. It emits only whitelisted numeric CPU-frequency reference fields, native readings and frequency-sysctl availability. No process/host information or raw Apple output is saved. Matching does not prove equal definitions or exactly synchronized windows; this is an initial cross-check.

No live administrator trace, end-to-end accuracy validation or helper overhead measurement has completed yet. Next step is to review these aggregate reports, then decide whether a minimal direct native tracing prototype is justified. The current unavailable Active time graph remains honest while this is unresolved.
