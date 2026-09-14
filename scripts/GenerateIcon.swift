import AppKit
import Foundation

// Keep the app icon available to Finder and Launchpad before the app runs.
struct IconArtwork {
    static func icon() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.15, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 56, yRadius: 56).fill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 35, y: 67)); path.line(to: NSPoint(x: 103, y: 181)); path.line(to: NSPoint(x: 151, y: 112)); path.line(to: NSPoint(x: 180, y: 151)); path.line(to: NSPoint(x: 225, y: 67)); path.close()
            NSGradient(starting: .systemTeal, ending: .systemGreen)?.draw(in: path, angle: 65)
            return true
        }
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let artwork = IconArtwork.icon()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        artwork.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
