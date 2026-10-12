#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/build.sh
codesign --verify --strict "build/Task Manager.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
archive="TaskManager-v${version}-macOS-arm64.zip"
mkdir -p build/releases
staging=$(mktemp -d "${TMPDIR:-/tmp}/taskmanager-release.XXXXXX")
trap 'rmdir "${staging}" 2>/dev/null || true' EXIT
(cd build && COPYFILE_DISABLE=1 /usr/bin/zip -q -X -r "${staging}/${archive}" "Task Manager.app")
mv "${staging}/${archive}" "build/releases/${archive}"
(cd build/releases && shasum -a 256 "${archive}" > SHA256SUMS.txt)
print "Packaged build/releases/${archive}"
