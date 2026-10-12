# Windows Task Manager visual reference catalog

Reviewed 2026-10-10. This is the implementation reference for preserving Task Manager's information architecture while applying native macOS materials, controls, SF Symbols and typography. Screenshots are external design references only: the app bundles no remote resources and makes no network requests.

## Baseline and inspection method

Use the Windows 11 sidebar-era Task Manager, with its newer title-bar search field, rather than the older tab-strip interface. The referenced captures span versions: recent Settings and App history frames supplement older clear column-menu captures. They establish layout and affordances; they do **not** establish that every capture comes from a single Windows build. The 2021 Services screenshot was inspected and rejected for chrome/layout because it still uses tabs.

Microsoft's primary announcements describe the [sidebar, per-page command bars, Settings and dark theme](https://blogs.windows.com/windows-insider/2022/02/16/announcing-windows-11-insider-preview-build-22557/) and [later filtering/theme changes](https://blogs.windows.com/windows-insider/2022/11/18/announcing-windows-11-insider-preview-build-25247/). Third-party captures below are used as visual evidence, not authority for implementation APIs.

Every frame marked **inspected** was opened as an image in the Codex browser and examined as rendered pixels. Dimensions are the image's natural dimensions. Geometry is an approximate visual measurement, not a pixel-perfect executable specification.

## Shared shell

The [modern Services frame](https://us.v-cdn.net/6029997/uploads/73RQIDX0L7PI/screenshot-2024-03-07-172808.png) is 951 × 730. It has roughly 52 px of title/search chrome, a 235 px expanded sidebar, then a 54 px command bar. Content begins at approximately x=235, y=106. The content pane fills the rest of the window; no dashboard cards or overview statistics displace its table.

The app title/icon sit at the top left, search is centered within the top chrome, and the hamburger sits above navigation. Navigation order is Processes, Performance, App history, Startup apps, Users, Details, Services. Settings is anchored to the bottom. Selected navigation uses a soft neutral rectangle and a thin accent marker. Sidebar rows are roughly 40 px in this frame. macOS may use a native glass selection pill but keeps order, proportions and anchors.

Each command bar places a small semibold page name left and contextual icon/text actions right. Avoid oversized page headings, descriptive subtitles and extra count bars. Content is dense: approximately 20–24 px Windows rows and thin column separators. Mac mode may use 27 px rows for native legibility. Accent heatmap cells, selection and sorting affordances are functional parts of the composition.

## Processes — inspected

[Frame, 1000 × 464](https://www.elevenforum.com/attachments/task_manager_processes_column_details-png.31828/) · [source tutorial](https://www.elevenforum.com/t/add-or-remove-columns-in-task-manager-in-windows-11.7173/)

The command bar has Run new task, End task and Efficiency mode, followed by a menu. Name is the wide leading column; Status follows. Resource columns display a total above their label within the header. The capture also enables PID, GPU, GPU engine, Power usage and Power usage trend. The body groups Apps and Background processes. App rows show icons and disclosure chevrons; their subprocesses indent beneath them. Resource cells have low-intensity accent fill with stronger fill for higher usage. Group headings are plain table rows, not raised cards. The header context menu checks available column names and ends with a Resource values submenu. Preserve status, grouped rows, column reordering and header totals. Unsupported Mac counters show dashes; Windows Efficiency mode remains disabled with an explanation.

## Performance

[Performance frame, inspected by the main implementation agent](https://cdn.mos.cms.futurecdn.net/t7BfxETqA4dDS999ER8Y5J.jpg) · [source article](https://www.windowscentral.com/whats-new-task-manager-windows-11-version-22h2). Additional [Microsoft CPU frame, inspected](https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/media/support-tools-task-manager/task-mgr-cpu.png).

Preserve the secondary resource rail, selected resource heading/model, grid charts, legends/axes and bottom metric/specification blocks. The rail pairs each small outlined chart with a resource name and two compact lines of usage/model information. CPU uses a blue grid chart and utilization/speed followed by process/thread/handle counts and uptime; specifications align in a separate right block. Logical-processors mode subdivides the same chart footprint rather than create unrelated cards. Memory uses a purple chart plus a horizontal composition bar, in-use/available/committed/cached values and hardware fields. Disk uses a green active-time chart above a smaller transfer-rate chart, read/write markers and capacity/type fields. Network uses an orange throughput graph with distinct sent/received traces, send/receive statistics and adapter/address fields. GPU uses engine charts and memory charts, with labels even where a Mac cannot supply a metric. Every unavailable Mac field remains a dash; chart gaps must not become invented idle samples. Merely showing an overview graph does not match this page.

### Performance subpage frames — individually inspected

- [Memory, 1611 × 874](https://windowsreport.com/wp-content/uploads/2023/09/compressed-memory-w11.png) · [source](https://windowsreport.com/memory-compression-windows-11/). A wide purple usage chart, composition bar beneath, three pairs of values at lower left and hardware specifications at lower right. The small rail chart is filled and outlined.
- [Disk, 1657 × 1003 desktop capture](https://cdn.mos.cms.futurecdn.net/V3BHRP5rtJRsPQyHyEuK4Q.jpg) · [source](https://www.windowscentral.com/whats-new-task-manager-windows-11-version-22h2). Active-time chart is approximately four times the height of the transfer-rate strip. Two value rows and a compact specification block occupy the bottom.
- [Ethernet, 2141 × 1163](https://forums.truenas.com/uploads/default/original/2X/1/17d3f43cdeff85b442b420843de344d9ffda52ca.jpeg) · [source](https://forums.truenas.com/t/setting-up-smb-multichannel-in-truenas-scale/3613). This modern dark capture uses pink traces. Send/Receive values stack below the chart at left; adapter name, connection type, IPv4 and IPv6 form an adjacent aligned block.
- [GPU, 1045 × 765](https://ankitdeshmukh.com/post/2025-02-07-running-llm-locally-setting-up-deepseek-r1/Configuration.png) · [source](https://ankitdeshmukh.com/post/2025-02-07-running-llm-locally-setting-up-deepseek-r1/). Four purple engine charts form a two-by-two grid: 3D, Copy, Video Encode, Video Decode. Two full-width short charts follow for Dedicated and Shared GPU memory. The bottom has utilization/memory/temperature values at left and driver/system specifications at right. This layout is still useful with explicitly unavailable Mac utilization samples.

## App history — inspected

[Frame, 1000 × 651](https://www.elevenforum.com/attachments/task_manager_app_history-1-png.115653/) · [source tutorial, November 2024](https://www.elevenforum.com/t/view-app-resource-usage-history-in-task-manager-in-windows-11.30387/)

The title bar includes search, and the page command bar has Run new task and an overflow menu. Below it is a small resource-history date line and the Delete usage history link, then a dense table. Standard leading columns are Name, CPU time, Network, Metered network and Notifications. The shown header menu additionally enables Non-metered network, Downloads and Uploads. Numeric history cells use an accent heatmap; CPU time is formatted as h:mm:ss. The older Tile updates label should not define this newer capture. The Mac implementation keeps the standard column slots with dashes for network/notification data, adds observed disk counters as optional columns, and clearly labels its recording interval and local-only history. Recording is an explicit local control; it must not imply Windows history exists on a Mac.

## Startup apps — inspected

[Frame, 750 × 335](https://www.elevenforum.com/attachments/task_manager_startup-apps_column_details-png.31829/) · [source tutorial](https://www.elevenforum.com/t/add-or-remove-columns-in-task-manager-in-windows-11.7173/)

The command bar displays Run new task, Enable, Disable, Properties and overflow. A small Last BIOS time label sits above the table at the right. The default column order is Name, Publisher, Status, Startup impact; names have app icons. The screenshot header menu lists optional Startup type, Disk I/O at startup, CPU at startup, Running now, Disabled time and Command line. Table rows are approximately 20 px in this scaled capture. Keep name/publisher/status/impact order, plain rows and wide name column. On Mac, launch-agent configuration and runtime load state cannot establish login permission, publisher identity or measured startup impact. Show Publisher as a dash and Startup impact as Not measured. Actual configuration paths are available through native Properties and Open file location. Open Login Items is the supported startup-management route.

## Users — inspected

[Frame, 750 × 290](https://www.elevenforum.com/attachments/task_manager_users_column_details-png.31830/) · [source tutorial](https://www.elevenforum.com/t/add-or-remove-columns-in-task-manager-in-windows-11.7173/)

Command actions are Run new task, Disconnect, Manage user accounts and overflow. The table starts with User, Status, CPU, Memory, Disk, Network, then optional GPU/GPU engine. Resource totals are shown in the header. A user row has an avatar, disclosure chevron and process count appended to its name. Expanding it exposes that user's processes. The header menu includes optional ID, Session and Client name plus resource columns/Resource values. Preserve grouping rather than repeat one user's aggregate totals for each login session. Mac mode totals the accessible processes once per user, exposes expandable process rows, and keeps unavailable per-process Network cells as dashes. Disconnect remains disabled because the app does not implement session termination; Manage user accounts maps to native account settings.

## Details — inspected

[Frame, 1000 × 380](https://www.elevenforum.com/attachments/task_manager_details_column_details-1-png.31825/) · [source tutorial](https://www.elevenforum.com/t/add-or-remove-columns-in-task-manager-in-windows-11.7173/)

This is a flat process table, not the grouped Processes view. The command bar has Run new task, End task and Properties. Visible columns are Name, PID, Status, User name, CPU, Memory, Architecture, Description. Rows are dense, with executable icons and no colored resource overview above them. Header context menu: Hide column and Select columns. The [second menu frame](https://www.elevenforum.com/attachments/task_manager_details_column_details-2-png.31826/) and [Select columns dialog, 356 × 395](https://www.elevenforum.com/attachments/task_manager_details_column_details-3-png.31831/) were also inspected. The scrollable checkbox dialog has an instruction line and OK/Cancel buttons; the visible portion includes PID, Status, User name, CPU and memory-related counters. Offscreen checkbox choices were not verified. Mac-specific fields such as threads, start time, priority and executable path may be optional additions without displacing this core layout. Preserve stable PID identity, sortable numeric counters and working local process actions.

## Services — inspected

[Modern frame, 951 × 730](https://us.v-cdn.net/6029997/uploads/73RQIDX0L7PI/screenshot-2024-03-07-172808.png) · [source discussion](https://community.acer.com/en/discussion/701852/predator-sense-not-working-anymore-what-predator-services-even-dont-show-in-the-task-manager)

The command bar shows Run new task, Start, Stop, Restart and overflow. Columns are Name, PID, Description, Status, Group. No top summary cards, footer inspector or separate inventory list. Service names have small gear icons; PID is blank when stopped. The wide Group column displays actual Windows service-group strings. Mac mode maps these slots to launchd name, reported PID, executable/description, reported runtime state and launch-job kind. A configured plist must not be labeled Running without runtime evidence. Start/Stop/Restart remain disabled when unsupported; inspection, file reveal, copy and refresh remain usable. The [older Services context-menu frame](https://www.elevenforum.com/attachments/task_manager_services-min-png.14820/) was also inspected: Start, Stop, Restart, Open Services, Search online, Go to details. Search online is omitted for the requested offline product.

## Settings — inspected

[Frame, 750 × 669](https://www.elevenforum.com/attachments/task_manager_default_start_page-webp.166025/) · [source tutorial, updated March 2026](https://www.elevenforum.com/t/change-default-start-page-for-task-manager-in-windows-11.7154/)

The title is small and aligned with content; no process command bar. Settings content has approximately 22 px top/side padding. Appearance contains a card with icon, App theme title, small subtitle and a right-aligned theme dropdown. General contains Default start page and Real time update speed cards. Window management expands to Always on top, Minimize on use, Hide when minimized. Other options expands to Show full account name, Show history for all processes and Ask me before applying Efficiency mode. Each row is approximately 53–59 px; section gaps are 22–28 px. Use native Mac controls/materials while preserving card order and expanding groups. Supported options persist and work. Windows-specific unsupported behaviors remain visibly disabled and explain their limitations. Add the Mac interface-style picker and local-history information without replacing the core structure.

## Fidelity checklist

- Keep the complete eight-item sidebar and page order, including bottom Settings.
- Keep each page's command-bar action order; explain unavailable Mac actions rather than create fictional behavior.
- Keep Windows' table column order and density; place Mac additions behind optional columns.
- Processes groups and Users disclosure rows must expand/collapse. Details remains flat.
- Numeric sorting, draggable columns, header menus, selected-row menus, Properties and local file reveal should work.
- Performance needs separate CPU/memory/disk/network/GPU compositions with proper grids and labels, not one reused dashboard.
- Apply Liquid Glass to chrome/navigation and native controls, keeping data/chart surfaces readable and respecting Reduce Transparency.
- Use real local measurements. Dashes explicitly represent unavailable counters; never plot invented zero samples.
- Test both appearances, light/dark, resized windows and page navigation against rendered frames.
