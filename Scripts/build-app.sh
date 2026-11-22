#!/bin/sh
# Builds dist/ByeSlides.app with its Quick Look extension.
#
#   SIGN_IDENTITY   codesign identity, e.g. "Developer ID Application: …". Default: ad hoc, for this Mac only.
#   NOTARY_PROFILE  notarytool keychain profile. When set, the app is notarized and stapled.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product ByeSlides
swift build -c release --product ByeSlidesQuickLook
bin=$(swift build -c release --show-bin-path)
resources=Sources/ByeSlidesCore/Resources
app=dist/ByeSlides.app
appex="$app/Contents/PlugIns/ByeSlidesQuickLook.appex"

# Start from an empty bundle so files removed from the project do not linger.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$appex/Contents/MacOS" "$appex/Contents/Resources"

cp "$bin/ByeSlides" "$app/Contents/MacOS/ByeSlides"
cp Packaging/Info.plist "$app/Contents/"
cp Packaging/AppIcon.icns "$app/Contents/Resources/"
cp -R Packaging/zh-Hans.lproj "$app/Contents/Resources/"
cp -R "$resources/." "$app/Contents/Resources/"

cp "$bin/ByeSlidesQuickLook" "$appex/Contents/MacOS/ByeSlidesQuickLook"
cp Packaging/QuickLook/Info.plist "$appex/Contents/"
# Only the small files. The extension reads the 25 MB font from the app around it.
for file in markdown-it.min.js purify.min.js reading.js reading.css; do
    cp "$resources/$file" "$appex/Contents/Resources/"
done

identity=${SIGN_IDENTITY:--}
if [ "$identity" = "-" ]; then
    set --
else
    # Notarization requires the hardened runtime and a secure timestamp.
    set -- --options runtime --timestamp
fi
codesign --force "$@" --sign "$identity" --entitlements Packaging/QuickLook/QuickLook.entitlements "$appex"
codesign --force "$@" --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    archive=dist/ByeSlides.zip
    ditto -c -k --keepParent "$app" "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    rm "$archive"
fi
echo "$app"
