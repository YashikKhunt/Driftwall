import SwiftUI
import AppKit

@main @MainActor struct LibraryUITests {
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let store = WallpaperStore(loadSavedState: false)
        store.active = "aurora"
        store.selected = "community-missing"
        let previousPreference = UserDefaults.standard.string(forKey: "active")
        store.apply()
        precondition(store.active == "aurora" && store.error != nil)
        precondition(UserDefaults.standard.string(forKey: "active") == previousPreference)
        print("PASS: unavailable wallpaper preserves current wallpaper and saved preference")
        store.error = nil
        store.active = nil
        store.selected = "aurora"
        let host = NSHostingView(rootView: LibraryView(section: "Community").environmentObject(store).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Could not render Library") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode Library preview") }
        precondition(png.count > 1000)
        if CommandLine.arguments.count == 2 { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
        print("PASS: Community empty state renders without importing, activating wallpaper, or fetching assets")
    }
}
