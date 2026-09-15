#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Driftwall.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache-driftwall"
python3 scripts/validate-community.py "$PWD/Community"
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache-driftwall" -target "$(uname -m)-apple-macosx14.0" Sources/VideoSafety.swift Sources/CommunityCatalog.swift Tests/ValidateCommunityMedia.swift -o build/ValidateCommunityMedia -framework AVFoundation -framework AppKit
build/ValidateCommunityMedia "$PWD/Community"
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache-driftwall" -target "$(uname -m)-apple-macosx14.0" Sources/*.swift -o "$APP/Contents/MacOS/Driftwall" -framework SwiftUI -framework AppKit -framework AVFoundation -framework MetalKit -framework IOKit -framework ServiceManagement
xcrun swiftc -module-cache-path "$PWD/build/module-cache-driftwall" scripts/GenerateIcon.swift -o "$PWD/build/GenerateIcon" -framework AppKit
"$PWD/build/GenerateIcon" "$PWD/build/AppIcon.iconset"
iconutil -c icns "$PWD/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
# Replace only generated bundled resources so withdrawn media cannot linger.
rm -rf "$APP/Contents/Resources/Community"
ditto Community "$APP/Contents/Resources/Community"
codesign --force --sign - "$APP"
echo "Built: $APP"
