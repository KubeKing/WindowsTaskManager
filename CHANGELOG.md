# Changelog

## Unreleased

- Add a granular memory-pressure curve using Activity Monitor’s native kernel reading and fixed 0–100 scale, with independent green/yellow/red pressure-state colors, the shared graph window and explicit unavailable gaps.

- Use a fixed configurable 30-second to 10-minute time window across every Performance graph; new samples scroll without compressing history.
- Always show native CPU/GPU **Temp · avg** summaries beside Utilization. A saved graph-only toggle adds temperature-colored dashed history with a separate 20–100 °C scale and five labeled ticks; sampling continues while hidden. Logical processor charts omit temperature UI; GPU temperature appears only in utilization boxes. The color guide lives in Settings rather than chart footers. No admin helper or external dependency.

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
