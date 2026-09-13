#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Scenes.swift Tests/RenderSmoke.swift -o build/RenderSmoke -framework AppKit -framework MetalKit
build/RenderSmoke
