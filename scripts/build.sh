#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Driftwall.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache" -target "$(uname -m)-apple-macosx14.0" Sources/*.swift -o "$APP/Contents/MacOS/Driftwall" -framework SwiftUI -framework AppKit -framework AVFoundation -framework MetalKit -framework IOKit -framework ServiceManagement
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $APP"
