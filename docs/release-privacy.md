# Public release privacy

The initial public repository is a clean snapshot, with a new root commit authored as Trey using the GitHub private commit address associated with KubeKing. Private local development history is not pushed.

The export includes the app source, tests, build scripts, icon and public documentation. Internal planning notes, third-party reference screenshot copies, local diagnostic records, build caches, preferences and monitoring history are excluded. Windows design references remain linked in the reference catalog.

Local generation paths are removed from the icon notes. Release builds remap source paths and strip debug information. The app ZIP contains only the app bundle, without extended attributes or resource forks. The DMG contains that same bundle and an Applications shortcut, without development logs, user preferences or collected monitoring data. Its mounted files are checked for personal metadata; a generic two-byte macOS provenance flag may be supplied by the OS.

Before publication, the source export and unpacked app are scanned for personal email addresses, local user paths, known account identifiers beyond the public GitHub repository URL, credential patterns and unexpected files. Image metadata is inspected, commit metadata is checked, and release archive contents and checksums are verified. These checks cover the published files and commit history; they do not change the GitHub account's existing public profile.

Subsequent development commits use the GitHub-provided private commit address associated with KubeKing, preserving account attribution without publishing a personal email. The original generic address incorrectly linked the v1 root commit to a different GitHub account. On 2026-10-12, an explicitly approved metadata-only rewrite corrected the root commit and v1.0.0 tag to KubeKing. The source tree and release downloads remain identical; existing clones must resync to the corrected history.
