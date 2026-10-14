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


## Logical core labels and time axis — 2026-10-12

All 59 tests in 11 suites passed, followed by optimized build, signature, plist and collector checks. Core-type mapping is keyed by IORegistry logical-cpu-id, independent of enumeration order; malformed, unknown, out-of-range or duplicate IDs stay unknown. The map is read once with static hardware metadata. No dependency was added. The registry mapping approach was checked against [hwloc's Darwin topology implementation](https://github.com/open-mpi/hwloc/blob/master/hwloc/topology-darwin.c).

The native dark Windows appearance was visually and accessibly verified: each CPU chart has a P/E badge, the legend spells out Performance/Efficiency, and the redundant utilization heading is removed for logical charts. Bare time endpoints are replaced by a duration ago and Latest sample; the latter remains accurate during pauses. The plot scaling and bounded sample retention are unchanged. On the development Mac, OS logical IDs 0–5 were efficiency cores and 6–9 were performance cores.


## Performance context menus — 2026-10-12

The CPU chart right-click menu reproduced the refresh issue: its submenu disappeared during ongoing sampling. CPU chart and resource-row menus now use a transparent native AppKit view, snapshot their items only on opening, and leave the tracked menu untouched when SwiftUI updates. Normal clicks and scrolling pass through the native overlay.

The updated build passed all 59 tests in 11 suites, optimized build, signature, plist and real collector checks. Native UI verification held the chart menu and its graph submenu open across repeated live updates, then successfully selected Logical processors. Right-clicking an individual logical CPU and toggling kernel times added the dashed kernel overlays; the prior setting was restored afterward. The resource-row menu also remained present while readings changed, and normal Memory/CPU row selection continued to work. The actual native interaction is the regression check; no synthetic unit test claims to reproduce AppKit menu tracking. No external dependency was added.


## Process network and resource headers — 2026-10-12

All 65 tests in 12 suites passed, followed by optimized build, signature, plist and real collector checks. New coverage validates per-flow baselines and aggregation, counter resets, socket closure, reused process IDs, stale samples, malformed counters and the tracked-flow limit. The live collector attributed experimental TCP/UDP rates to 23 processes without administrator access on the development Mac.

A controlled localhost TCP test transferred four 65,536-byte bursts after baselines were established. The production collector matched the test process identity and reported exactly 262,144 received bytes and 262,144 sent bytes over the observation window, including the asynchronous final query. Only aggregate validation results were retained in this report. The initial native probe exposed zero process identities until each source descriptor was queried; that required initialization is now part of the reader.

Native UI checks verified real app-group rates and Network sorting in Processes, rates for accessible helper processes in Details, and the aggregate in Users. Windows Power usage/trend columns are removed. The resource-header cell now clips custom text to its actual visible column, so AppKit's trailing filler cannot repeat the last resource total. Network was hidden and restored while Disk and Network alternated as the last column; neither repeated its total across the filler. The column menu remained open during ongoing updates.

The native reader uses one utility queue, asynchronous queries at the existing sampling interval, per-flow baselines and cached kernel process identities. It retains only identity and byte counters; callback endpoints and names are discarded. No third-party dependency, subprocess, packet capture, administrator helper or remote request was added. Rates cover observed TCP/UDP socket owners, include loopback, may omit short-lived/unobserved traffic, and are not physical-interface totals. Unsupported or inaccessible readings remain unavailable. Network history is not yet recorded. Undocumented API compatibility is verified only on this development Mac.

A 30-second visible Processes-page spot check measured 2.47 CPU seconds (8.23% of one core), ending RSS 209.3 MiB and ending physical footprint 74.4 MiB. Other apps remained active and compression/shared pages affected memory accounting. There is no controlled before/after comparison for this addition; no CPU or RAM reduction is claimed. The final smoke sample collected in 9.34 ms.

Public source and the built executable passed local-path and credential-pattern scans. Raw probes, process lists, screenshots, endpoint data and local runtime reports remain excluded from public source. The existing v1.0.0 release download is unchanged.


## GPU chart selectors and disk timing — 2026-10-12

All 72 tests in 14 suites passed, followed by optimized build, signature, plist and native collector checks. New tests cover independent persisted chart slots, unknown settings and index guards, metric units and missing readings, driver counter validation, resets, overlapping I/O and intervals without completed requests. A memory conversion regression was caught by the tests and corrected before the final successful run.

All four GPU charts now have stable native selectors. UI checks covered selectable utilization, renderer, tiler and memory metrics, an explicitly unavailable Video Decode graph, byte-versus-percent scaling, independent chart changes, selection persistence after quit/relaunch and both dark appearances. A native menu remained tracked across live sampling and successfully applied a selection afterward. The fourth default chart uses live GPU memory in use.

The development Mac exposes completed read/write operation counts and cumulative per-request elapsed nanoseconds. Their interval deltas now provide average completed-I/O response time; a live disk-page check showed 0.05 ms. Concurrent requests can overlap, so these durations are not converted into a fabricated active-time percentage. The graph explains that a validated busy-time counter is unavailable and distinguishes active time from filesystem capacity used. Timing uses the existing driver query, with no additional polling. The interpretation was checked against Apple's [IOBlockStorageDriver source](https://github.com/apple-oss-distributions/IOStorageFamily/blob/main/IOBlockStorageDriver.cpp).

Targeted accelerator/media-driver inspection and IOReport descriptor research found utilization, renderer, tiler and GPU memory readings, plus media energy/bandwidth/power-state channels. No verified separate Video Decode, Video Encode or Copy busy percentage was established on this Mac. Those choices stay clearly unavailable; energy, bandwidth and power residency are not substituted for utilization. This is a hardware/OS verification limit, not a claim that media counters can never be implemented. Research probes are excluded, and no additional runtime IOReport subscription was added.

No external dependency, privileged helper or remote request was added. Raw registry/channel probes, screenshots and local runtime reports remain excluded from public source. The existing v1.0.0 release download is unchanged.


## v1.1.0 release verification — 2026-10-14

The exact release source passed all 72 tests in 14 suites, optimized build, strict ad-hoc signature, plist and native collector checks. Version metadata is 1.1.0, build 2; About reads the bundled version. Existing bundle identifier, defaults domain and local history location remain unchanged. Native P/E CPU frequency, observed per-process network, physical/virtual storage and GPU driver readings succeeded without administrator access. No overall CPU/RAM reduction is claimed.

The administrator-helper investigation and standalone admin diagnostic are excluded from this release's source tree. No helper target, LaunchDaemon, privileged installer, administrator telemetry call, new dependency or runtime network client is included. Disk active time, nominal CPU base speed and unsupported GPU-engine percentages stay unavailable. The private local research remains preserved outside the public release checkout.

Release packaging includes only the app executable, Info.plist, icon and signature. The source and unpacked ZIP passed local-path, personal-data and credential-pattern scans; archive entries and version/architecture were checked, the unpacked signature and collector verified, and the SHA-256 checksum validated. Raw diagnostics, preferences and monitoring history are excluded. The download remains ad-hoc signed and not notarized; existing macOS 27 / Apple silicon requirements are unchanged.
