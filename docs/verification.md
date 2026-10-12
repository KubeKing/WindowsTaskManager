# v1.0.0 verification

Verified on 2026-10-12 on Apple silicon, macOS 27, with the Swift 6.4 command-line toolchain.

`./scripts/verify.sh` passed all 45 Swift Testing tests across eight suites, built the optimized app, validated Info.plist, verified the ad-hoc signature and sampled real local counters.

Coverage includes GPU counter decoding and history, unified-memory comparison, rate baselines and resets, hardware discovery, process identity safety and disposable-child termination, query matching, local inventory parsing and bounded history persistence.

The release ZIP contains only the app bundle. Source paths are remapped, debug information is stripped, and archive extended attributes/resource forks are excluded. A SHA-256 checksum accompanies the download. Public source and unpacked app files were checked for personal identifiers, paths and credential patterns; private Git history is excluded.

The earlier development review exercised all pages, both appearances, light/dark styling, GPU memory enlargement and overlays, pause/resume, search, process actions and resizing. No app-owned network sockets were observed. No third-party runtime packages are declared.

This release has not been notarized or tested across other Mac hardware/OS versions. GPU property names are driver-specific; unsupported metrics remain unavailable. CPU/other memory is an explicitly labelled residual estimate, not an exact CPU-only allocation count.
