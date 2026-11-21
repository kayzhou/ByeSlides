#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
bin=$(swift build -c release --show-bin-path)
app=dist/ByeSlides.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ByeSlides" "$app/Contents/MacOS/ByeSlides"
cp Packaging/Info.plist "$app/Contents/"
cp Packaging/AppIcon.icns "$app/Contents/Resources/"
cp -R Packaging/zh-Hans.lproj "$app/Contents/Resources/"
cp -R Sources/ByeSlides/Resources/. "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "$app"
