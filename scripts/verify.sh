#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/taskmanager-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/taskmanager-swift"
# Command-line tools bundle Swift Testing; full Xcode installations support it too.
swift test --build-system native --scratch-path .build/native --disable-sandbox --cache-path "${TMPDIR:-/tmp}/taskmanager-cache" --disable-xctest --enable-swift-testing -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks
scripts/build.sh
"build/Task Manager.app/Contents/MacOS/TaskManager" --sample
codesign --verify --strict "build/Task Manager.app"
plutil -lint Resources/Info.plist
