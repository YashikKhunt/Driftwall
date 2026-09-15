#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache-driftwall
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache-driftwall" Sources/Scenes.swift Tests/RenderSmoke.swift -o build/RenderSmoke -framework AppKit -framework MetalKit
build/RenderSmoke

python3 -m unittest discover -s Tests -p 'test_community_validation.py'
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache-driftwall" -parse-as-library Tests/MakeVideo.swift -o build/MakeVideo -framework AppKit -framework AVFoundation
FIXTURE_DIR=$(mktemp -d "$PWD/build/community-fixtures.XXXXXX")
trap 'rm -rf "$FIXTURE_DIR"' EXIT
build/MakeVideo "$FIXTURE_DIR/fixture.mov"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache-driftwall" Sources/VideoSafety.swift Tests/VideoSafetyTests.swift -o build/VideoSafetyTests -framework AVFoundation
build/VideoSafetyTests "$FIXTURE_DIR/fixture.mov"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache-driftwall" Sources/VideoSafety.swift Sources/VideoLibrary.swift Tests/VideoLibraryTests.swift -o build/VideoLibraryTests -framework AVFoundation
build/VideoLibraryTests
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache-driftwall" Sources/VideoSafety.swift Sources/CommunityCatalog.swift Tests/CommunityCatalogTests.swift -o build/CommunityCatalogTests -framework AppKit -framework AVFoundation
build/CommunityCatalogTests "$FIXTURE_DIR/fixture.mov"

xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -D DRIFTWALL_TESTS -module-cache-path "$PWD/build/module-cache-driftwall" Sources/*.swift Tests/LibraryUITests.swift -o build/LibraryUITests -framework SwiftUI -framework AppKit -framework AVFoundation -framework MetalKit -framework IOKit -framework ServiceManagement
build/LibraryUITests "$PWD/build/community-preview.png"
