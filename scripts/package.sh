#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/build.sh
codesign --verify --strict "build/Task Manager.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
archive="TaskManager-v${version}-macOS-arm64.zip"
image="TaskManager-v${version}-macOS-arm64.dmg"
mkdir -p build/releases
staging=$(mktemp -d "${TMPDIR:-/tmp}/taskmanager-release.XXXXXX")
trap 'rm -rf -- "${staging}"' EXIT
(cd build && COPYFILE_DISABLE=1 /usr/bin/zip -q -X -r "${staging}/${archive}" "Task Manager.app")
mkdir "${staging}/dmg"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noqtn --noacl "build/Task Manager.app" "${staging}/dmg/Task Manager.app"
ln -s /Applications "${staging}/dmg/Applications"
/usr/bin/hdiutil create -volname "Task Manager" -srcfolder "${staging}/dmg" -fs HFS+ -format UDZO -nospotlight -noanyowners -ov "${staging}/${image}"
/usr/bin/hdiutil verify "${staging}/${image}"
mv "${staging}/${archive}" "${staging}/${image}" build/releases/
(cd build/releases && shasum -a 256 "${archive}" "${image}" > SHA256SUMS.txt)
print "Packaged build/releases/${archive} and build/releases/${image}"
