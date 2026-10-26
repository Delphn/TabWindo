#!/bin/zsh
# Development build: compiles TabWindo, signs it with your Apple Development certificate (so macOS keeps
# its permissions across rebuilds), installs it to /Applications and relaunches it.
#   ./build.sh          optimized build, like the one you ship
#   ./build.sh debug    debug build, with the --list and --snapshot tools
# For a public, notarized release use ./release.sh.
set -euo pipefail
cd "$(dirname "$0")"

config="${1:-release}"
app="TabWindo.app"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)/TabWindo"

bundle=".build/$app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin" "$bundle/Contents/MacOS/TabWindo"
cp Info.plist "$bundle/Contents/Info.plist"
# The Liquid Glass app icon, compiled from the Icon Composer document.
xcrun actool AppIcon.icon --compile "$bundle/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist .build/AppIcon-info.plist >/dev/null

identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
codesign --force --options runtime --sign "${identity:--}" "$bundle"

# Quit the running copy first. It gets SIGTERM, so it hands ⌘Tab back to macOS on the way out.
pkill -x TabWindo && sleep 0.5 || true
rm -rf "/Applications/$app"
ditto "$bundle" "/Applications/$app"
open "/Applications/$app"
echo "Installed /Applications/$app ($config, signed by ${identity:-ad-hoc})"
