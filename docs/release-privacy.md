# Public release privacy

The initial public repository is a clean snapshot, with a new root commit authored as Trey using a neutral non-personal email. Private local development history is not pushed.

The export includes the app source, tests, build scripts, icon and public documentation. Internal planning notes, third-party reference screenshot copies, local diagnostic records, build caches, preferences and monitoring history are excluded. Windows design references remain linked in the reference catalog.

Local generation paths are removed from the icon notes. Release builds remap source paths and strip debug information. The app ZIP contains only the app bundle, without extended attributes or resource forks; it does not contain development logs, user preferences or collected monitoring data.

Before publication, the source export and unpacked app are scanned for personal email addresses, local user paths, known account identifiers beyond the public GitHub repository URL, credential patterns and unexpected files. Image metadata is inspected, commit metadata is checked, and release archive contents and checksums are verified. These checks cover the published files and commit history; they do not change the GitHub account's existing public profile.
