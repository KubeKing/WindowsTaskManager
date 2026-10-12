# v1.0.0 verification

Verified on 2026-10-12 on Apple silicon, macOS 27, with the Swift 6.4 command-line toolchain.

`./scripts/verify.sh` passed all 45 Swift Testing tests across eight suites, built the optimized app, validated Info.plist, verified the ad-hoc signature and sampled real local counters.

Coverage includes GPU counter decoding and history, unified-memory comparison, rate baselines and resets, hardware discovery, process identity safety and disposable-child termination, query matching, local inventory parsing and bounded history persistence.

The release ZIP contains only the app bundle. Source paths are remapped, debug information is stripped, and archive extended attributes/resource forks are excluded. A SHA-256 checksum accompanies the download. Public source and unpacked app files were checked for personal identifiers, paths and credential patterns; private Git history is excluded.

The earlier development review exercised all pages, both appearances, light/dark styling, GPU memory enlargement and overlays, pause/resume, search, process actions and resizing. No app-owned network sockets were observed. No third-party runtime packages are declared.

This release has not been notarized or tested across other Mac hardware/OS versions. GPU property names are driver-specific; unsupported metrics remain unavailable. CPU/other memory is an explicitly labelled residual estimate, not an exact CPU-only allocation count.

## Menu and Performance fixes — 2026-10-12

The updated build passed 48 tests in nine suites, including visibility persistence, device identity changes, disconnected devices, all-hidden selection and restore behavior. The optimized build, plist, signature and real collector smoke check passed.

The released v1 More submenu was observed disappearing during live updates. Settings theme dropdowns showed the same refresh issue and were replaced with stable fixed-choice native controls. The replacement native More menu retained its open submenu across monitoring ticks and applied logical-processor selection. Hiding the selected CPU item switched to Memory; CPU stayed hidden after quit/relaunch and was restored from More → Performance items. Logical charts were visually checked for complete borders, per-core labels and spacing.

Runtime measurements used 45-second visible-window samples at a one-second update interval on the same Apple silicon Mac. CPU percentages below refer to one core; 3% is roughly 0.3% of a ten-core machine. Other apps remained running, so these are practical spot checks, not controlled benchmark averages. Physical footprint is reported separately because resident memory fluctuated with compression.

| Logical CPU page | CPU time | One-core CPU | Ending RSS | Ending physical footprint |
| --- | --- | --- | --- | --- |
| Released v1 | 1.34 seconds | 2.98% | 66.6 MiB | 113.5 MiB |
| Updated build | 1.35 seconds | 3.00% | 89.1 MiB | 124.4 MiB |

A separate Processes-page spot check measured v1 at 7.29 CPU seconds (16.2% of one core) and the updated build at 4.86 CPU seconds (10.8%) over 45 seconds. Prior navigation/warm-up and memory states differed, so this is suggestive, not a controlled estimate of improvement. Process-table memory is not compared across those sessions.

The chart workload showed no measurable CPU reduction and a higher memory footprint in this sample. No overall RAM saving is claimed. Reused byte formatters, removal of redundant process sorting, deferred inventory scans and collector autorelease pools eliminate avoidable work. An experimental lazy resource rail was discarded after worse measurements. Further reductions should target the process table and SwiftUI view/layout work with controlled profiling.

The runtime script supports an exact executable path and physical footprint readings for future comparisons. No external dependency, network client or helper was added. Raw process listings, profiles and local paths are excluded from this report. The v1 release download is unchanged; fixes are on the development branch.


## CPU frequency and storage follow-up — 2026-10-12

The final build passed all 57 tests in 11 suites, built the optimized app, validated Info.plist, verified the ad-hoc signature and sampled real counters. New coverage checks Hz/kHz table decoding, active-residency weighting, unsupported/mismatched states, verified APFS association, unknown capacity and exclusion of disk images from physical throughput totals. The anonymous disk-driver regression test failed before the storage fix and passed afterward.

The experimental native CPU reader returned live P-core and E-core GHz without administrator access on the development Apple silicon Mac. These are active-time cluster averages, excluding idle residency. Undocumented API compatibility has not been verified across other chips or macOS versions; unsupported readings remain unavailable. No external package, shell sampler, privileged helper or network client was added.

Native UI checks confirmed both measured speed fields, a used/available filesystem capacity bar above disk graphs, a named internal SSD with its startup volume, and a separately labelled virtual disk image. The empty card-reader driver is omitted. Switching between devices updates both visual and accessibility details; the capacity layout was checked in Windows and macOS appearances with dark styling. Physical capacity and shared APFS filesystem capacity are displayed separately and never summed. Capacity refreshes every 30 seconds, while transfer rates remain live.

The release download remains v1.0.0. These changes are on the development branch. Raw registry dumps, process lists, local screenshots and diagnostics are excluded from public source. No overall CPU or RAM reduction is claimed from this follow-up.
