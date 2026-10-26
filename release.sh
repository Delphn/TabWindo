#!/bin/zsh
# Public release: builds TabWindo for Apple silicon and Intel, signs it with your Developer ID, has Apple
# notarize it, and packages it as dist/TabWindo.dmg, ready to share.
#
# One-time setup:
#   1. A "Developer ID Application" certificate:
#      Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application.
#   2. Notarization credentials in your keychain (asks for an app-specific password from
#      account.apple.com → Sign-In and Security → App-Specific Passwords):
#        xcrun notarytool store-credentials tabwindo-notary --apple-id <your Apple ID> --team-id 84342V62ZL
set -euo pipefail
cd "$(dirname "$0")"

profile="${NOTARY_PROFILE:-tabwindo-notary}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate found: see the setup notes in release.sh."; exit 1; }

swift build -c release --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TabWindo"

dist="dist"
app="$dist/TabWindo.app"
rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/TabWindo"
cp Info.plist "$app/Contents/Info.plist"
xcrun actool AppIcon.icon --compile "$app/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "$dist/AppIcon-info.plist" >/dev/null
rm "$dist/AppIcon-info.plist"
# actool reports success even when it fails, so check for its output.
[[ -s "$app/Contents/Resources/AppIcon.icns" ]] || { echo "The app icon didn't compile." >&2; exit 1; }

codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict "$app"

# Notarize the app and staple the ticket to it, so it opens without a warning even offline.
ditto -c -k --keepParent "$app" "$dist/TabWindo.zip"
xcrun notarytool submit "$dist/TabWindo.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
rm "$dist/TabWindo.zip"

# The DMG: the app plus a shortcut to Applications, itself signed, notarized and stapled. Its name has no version,
# so the website's Download buttons always get the newest one from releases/latest/download/TabWindo.dmg.
dmg="$dist/TabWindo.dmg"
staging="$dist/dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "TabWindo" -srcfolder "$staging" -format UDZO -ov "$dmg" >/dev/null
rm -rf "$staging"
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"

spctl --assess --type execute -v "$app"
spctl --assess --type open --context context:primary-signature -v "$dmg"
echo "Ready to share: $dmg. Attach it to a GitHub release tagged v$version."
