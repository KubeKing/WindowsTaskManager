# Changelog

## 1.2.1 — 2026-10-16

- Add a compressed, read-only DMG containing Task Manager.app and an Applications shortcut for drag-to-install distribution.
- Keep the ZIP alternative and publish SHA-256 checksums for both downloads.
- Update installation instructions. Signing remains ad-hoc; this packaging change does not add Developer ID signing, notarization, an installer service or a runtime dependency.

## 1.2.0 — 2026-10-16

- Use a fixed configurable 30-second to 10-minute window across all Performance graphs; incoming samples scroll without compressing the timeline. Right endpoints read Now while monitoring and Paused when frozen.
- Add a granular memory-pressure curve using the native kernel reading used by the inspected Activity Monitor, with a fixed 0–100 scale and separate green/yellow/red pressure-state colors. Missing readings and sampling gaps remain blank.
- Always show readable CPU/GPU **Temp · avg** summaries beside Utilization. Independently saved graph toggles in Settings and chart right-click menus hide only overlays, temperature axes and chart badges; existing shared choices migrate automatically.
- Add dashed temperature history with a 20–100 °C axis and ticks at 20, 40, 60, 80 and 100 °C. Colors change at the chart thresholds between samples without carrying hotter colors into cooler tails or restarting the dash pattern.
- Keep GPU temperature overlays only on boxes set to GPU utilization. Omit unverified per-core temperature UI and move the temperature color guide to Settings.

Runs offline without administrator access, a helper or third-party packages. Temperature discovery and granular memory pressure use optional undocumented native interfaces; unsupported readings stay unavailable. Temperature bands are display guidance, not Apple hardware limits or proof of throttling. Existing Apple silicon / macOS 27 requirements remain unchanged.

## 1.1.0 — 2026-10-14

- Choose each GPU chart metric independently through stable native dropdowns, with choices retained across updates and unavailable engine metrics labelled explicitly.
- Populate disk average I/O response time from validated request counters and explain why active time differs from capacity used.
- Add experimental native TCP/UDP receive/send rates per process and app group, with PID-reuse protection and unavailable fallbacks; no helper or third-party package.
- Remove unsupported Windows Power usage/trend columns and fix duplicated resource totals when hiding the last table column.
- Keep CPU chart and Performance resource right-click menus stable across live monitoring updates.
- Label logical CPU charts with verified performance/efficiency core types and clarify graph time endpoints.
- Measure experimental native P/E CPU frequencies with validated IOReport residency and frequency tables; no administrator helper.
- Identify whole storage devices, distinguish disk images, and group verified attached volumes on their drive page.
- Add per-volume used capacity, percentage and available-space bars while keeping physical capacity separate.
- Keep the More menu, submenus and Settings dropdowns stable during live updates.
- Hide individual Performance items with preferences retained across app updates.
- Improve logical processor chart borders, contrast and per-core labels.
- Reuse formatting work, remove redundant sorting and defer startup/service inventory scans until needed.
- Document missing metrics by implementation feasibility and add physical footprint to the runtime measurement script.

Runs entirely offline without administrator access, a helper service or third-party packages. The admin-metrics research diagnostic is excluded from this release. Disk active time, nominal CPU base speed and unsupported GPU engines remain unavailable rather than estimated.

## 1.0.0 — 2026-10-12

Initial public release of Task Manager for Mac.

- Native Swift app with macOS Liquid Glass and Windows-inspired appearances, including light and dark themes.
- Live Processes, Details, CPU, memory, storage, network and supported GPU driver counters.
- Enlarged GPU memory graph with optional total, system-used, GPU-used and CPU/other estimate overlays.
- Local startup/service inventories, user sessions, safe process actions and opt-in bounded app history.
- Dark charcoal waveform app icon.
- Offline runtime with Apple frameworks only; no telemetry, accounts, update checker or third-party dependencies.

Requires Apple silicon and macOS 27 or later. GPU counters depend on the local driver; unsupported metrics remain unavailable. CPU/other memory is a residual estimate because CPU/GPU allocations share memory. Windows-only controls are documented in the README. The downloadable app is ad-hoc signed and is not notarized.
