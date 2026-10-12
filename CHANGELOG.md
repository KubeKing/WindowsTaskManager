# Changelog

## 1.0.0 — 2026-10-12

Initial public release of Task Manager for Mac.

- Native Swift app with macOS Liquid Glass and Windows-inspired appearances, including light and dark themes.
- Live Processes, Details, CPU, memory, storage, network and supported GPU driver counters.
- Enlarged GPU memory graph with optional total, system-used, GPU-used and CPU/other estimate overlays.
- Local startup/service inventories, user sessions, safe process actions and opt-in bounded app history.
- Dark charcoal waveform app icon.
- Offline runtime with Apple frameworks only; no telemetry, accounts, update checker or third-party dependencies.

Requires Apple silicon and macOS 27 or later. GPU counters depend on the local driver; unsupported metrics remain unavailable. CPU/other memory is a residual estimate because CPU/GPU allocations share memory. Windows-only controls are documented in the README. The downloadable app is ad-hoc signed and is not notarized.
