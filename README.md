# Task Manager for Mac

A Swift system monitor with Windows Task Manager's familiar navigation and dense process tables, finished with native macOS styling. The default appearance uses Liquid Glass; a Windows appearance is available in the toolbar. All data stays on this Mac.

## Run

Requires an Apple silicon Mac on macOS 27 or later.

Download **TaskManager-v1.0.0-macOS-arm64.zip** from [Releases](https://github.com/KubeKing/WindowsTaskManager/releases/latest), unzip it, and move **Task Manager.app** to Applications. The download is ad-hoc signed, not Developer ID signed or notarized; macOS Gatekeeper may block it. Building from source is also supported.

To build, install Apple's Swift command-line tools. There are no third-party packages to download.

```sh
./scripts/build.sh
open "build/Task Manager.app"
```

The dark app icon is bundled artwork in `Resources/AppIcon-dark.png`; the build creates the macOS icon sizes locally. Image generation is only used while designing the icon.

The build produces `build/Task Manager.app`, signed locally with an ad-hoc signature. Keep or move the app wherever you prefer; no installer, account, helper daemon, or network access is needed. `./scripts/package.sh` builds a release ZIP and SHA-256 checksum without local file metadata.

## Use

- **Processes / Details:** search names, users, paths or PIDs; click headers to sort; select a process to inspect, copy details, reveal its executable, quit or force quit. Process actions validate its creation time as well as PID.
- **Performance:** separate CPU, Memory, disk, network-adapter and GPU layouts based on Windows reference frames; switch CPU between overall and logical-processor graphs, and toggle kernel times. Unsupported counters remain dashes. The initial sample establishes rate baselines. Per-process CPU uses a whole-machine 0–100% convention, unlike Activity Monitor's per-core convention.
- **Logical CPU charts:** P/E badges identify performance and efficiency cores using OS logical CPU IDs; unknown types stay unknown. The time axis shows the visible span ago through the latest sample, including when monitoring is paused.
- **CPU speed:** experimental native IOReport readings show active-time-weighted P-core and E-core GHz without administrator access. Unknown states, unsupported tables or unavailable private APIs stay marked unavailable.
- **Storage:** drives are labelled by type and BSD device; disk images are explicitly virtual. Attached user volumes share the drive page, with used-capacity bars and available space. APFS shared capacities are shown separately and never added together.
- **Performance visibility:** right-click a resource to hide it, or use **More → Performance items** / **Settings → Performance items** to show or hide individual CPUs, memory, disks, adapters and GPUs. Choices are stored in the app's version-independent preferences and survive app updates. **Show all performance items** restores the list.
- **GPU memory comparison:** in Performance → GPU, click **Enlarge** beside GPU memory in use (or double-click the graph). Turn on **Overlay total, GPU and CPU memory** for capacity, system usage, GPU usage and an explicitly labelled CPU/other estimate. **Restore** returns to the GPU overview. CPU/other is system used minus this GPU's in-use counter; shared allocations prevent an exact CPU-only split.
- **Startup apps / Services:** read-only inventory of accessible launch agents, daemons and loaded user jobs. Open Login Items in System Settings to manage other apps' startup behavior. Configured jobs are not assumed to be running.
- **Users:** login sessions reported by the local session database, expandable process rows and attributable resource totals.
- **App history:** optional local resource history. Enable it in Settings; it records only observed usage while the app is sampling. Data never leaves this Mac. Clear it from the history page.
- **Settings:** appearance, light/dark/system color mode, default start page, update frequency, always on top and optional history. Monitoring slows when the window is hidden/minimized. Closing the app stops monitoring.

Shortcuts: ⌘N Run New Task, ⌘R Refresh, ⇧⌘P Pause/Resume, ⌘I Inspect, ⇧⌘C Copy Process Details, ⌘, Settings, ⌘Q Quit.

macOS restricts some protected process fields and administrative actions. Unavailable values are marked instead of invented. Available GPU utilization, renderer/tiler activity and memory counters are read directly from the local driver. Driver-specific fields remain unavailable if absent; separate Windows GPU engines and Neural Engine counters are unavailable. Windows affinity/UAC/efficiency-mode controls, and arbitrary other-app Login Item toggles are not exposed as working features. Use native macOS system controls for protected administration.

## Verify

```sh
./scripts/verify.sh
```

Tests exercise GPU driver decoding and history, counter resets, rate baselines, process identity safety, real disposable child-process termination, search, launch plist parsing, and bounded local history. `TaskManager --sample` runs a real local collector diagnostic without opening the interface.

Preferences use the `local.swift.TaskManager` defaults domain. Optional history lives in `~/Library/Application Support/TaskManager`. No launch-at-login item or permanent background process is installed.

Visual references for every page and performance subpage are cataloged in [docs/windows-reference.md](docs/windows-reference.md). Runtime measurements and acceptance checks are recorded in [docs/verification.md](docs/verification.md).

Unavailable metrics and controls are classified in [the metric inventory](docs/metric-inventory.md), including features that can be added versus Windows concepts with no exact Mac equivalent.
