#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="build/Iconify.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp AppLogo.png AppIcon.icns "$APP/Contents/Resources/"
xcrun swiftc -parse-as-library Iconify.swift -o "$APP/Contents/MacOS/Iconify" -framework SwiftUI -framework AppKit -target arm64-apple-macosx13.0 -module-cache-path build/module-cache
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
