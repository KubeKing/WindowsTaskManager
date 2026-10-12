#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/taskmanager-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/taskmanager-swift"
swift build --build-system native --scratch-path .build/native --disable-sandbox --cache-path "${TMPDIR:-/tmp}/taskmanager-cache" -c release -Xswiftc -file-prefix-map -Xswiftc "${PWD}=/TaskManager" -Xswiftc -debug-prefix-map -Xswiftc "${PWD}=/TaskManager"
mkdir -p "build/Task Manager.app/Contents/MacOS" "build/Task Manager.app/Contents/Resources"
cp .build/native/release/TaskManager "build/Task Manager.app/Contents/MacOS/TaskManager"
strip -S "build/Task Manager.app/Contents/MacOS/TaskManager"
cp Resources/Info.plist "build/Task Manager.app/Contents/Info.plist"
swift scripts/make-icon.swift build
iconutil -c icns build/AppIcon.iconset -o "build/Task Manager.app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "build/Task Manager.app"
print "Built ${PWD}/build/Task Manager.app"
