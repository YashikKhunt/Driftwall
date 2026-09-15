import SwiftUI
import AppKit
import MetalKit
import AVKit

// Explicit alias selects the property wrapper on SDKs that also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct DriftwallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = WallpaperStore()
    var body: some SwiftUI.Scene {
        MenuBarExtra("Driftwall", systemImage: "mountain.2.fill") {
            MenuControls().environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var libraryWindow: NSWindow?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    @MainActor static func showLibrary(store: WallpaperStore) {
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Driftwall"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = NSHostingView(rootView: LibraryView().environmentObject(store).preferredColorScheme(.dark))
            window.minSize = NSSize(width: 920, height: 650)
            window.center()
            libraryWindow = window
        }
        libraryWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}

struct MenuControls: View {
    @EnvironmentObject var store: WallpaperStore
    var body: some View {
        Text(store.active == nil ? "Driftwall" : store.activeName)
        Text(store.status)
        Divider()
        Button("Open Library") { AppDelegate.showLibrary(store: store) }
        Toggle("Launch at Login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLogin($0) }))
        if let error = store.error { Text(error) }
        Button(store.paused ? "Resume Wallpaper" : "Pause Wallpaper") { store.togglePause() }.disabled(store.active == nil)
        Button("Restore Original Desktop") { store.stop() }.disabled(store.active == nil)
        Divider()
        Button("Quit Driftwall") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct ScenePreview: NSViewRepresentable {
    var kind: Int
    var animated = false
    class Coordinator { var renderer: SceneRenderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.renderer = SceneRenderer(view: view, kind: kind)
        view.isPaused = !animated
        view.enableSetNeedsDisplay = !animated
        view.preferredFramesPerSecond = 24
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.kind = Float(kind)
        view.isPaused = !animated
        view.enableSetNeedsDisplay = !animated
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) { view.isPaused = true; view.delegate = nil }
}

struct VideoPreview: NSViewRepresentable {
    var url: URL
    class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var url: URL?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspectFill
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.player?.pause()
        context.coordinator.looper?.disableLooping()
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        context.coordinator.player = player; context.coordinator.url = url
        view.player = player
        // Video previews start paused; the user's desktop playback remains independent.
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause(); coordinator.looper?.disableLooping(); view.player = nil
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: WallpaperStore
    @ViewState private var section = "Discover"
    @ViewState private var search = ""
    @ViewState private var category = "All"
    @ViewState private var settings = false
    @ViewState private var videoToDelete: Video? = nil
    private let accent = Color(red: 0.48, green: 0.92, blue: 0.73)
    var selectedScene: Scene? { Scene.all.first { $0.id == store.selected } }
    var selectedVideo: Video? { store.videos.first { $0.id == store.selected } }
    private var visibleScenes: [Scene] {
        let catalog = section == "Discover" ? Array(Scene.all.prefix(6)) : Scene.all
        return catalog.filter {
            (section != "Library" || category == "All" || $0.category == category)
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }
    private var heading: String {
        switch section {
        case "Library": return "Every atmosphere."
        case "My videos": return "Make it yours."
        default: return "A little more alive."
        }
    }
    private var subtitle: String {
        switch section {
        case "Library": return "Browse the full collection by mood."
        case "My videos": return "Your videos. Your desktop. On repeat."
        default: return "Original scenes for your everyday escape."
        }
    }
    private var collectionLabel: String {
        switch section {
        case "Library": return "LIBRARY  ·  \(category.uppercased())"
        case "My videos": return "YOUR LIBRARY"
        default: return "THE COLLECTION"
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(heading).font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.importVideo() } label: { Label(store.importing ? "Importing…" : "Import video", systemImage: "plus") }
                        .buttonStyle(.bordered).disabled(store.importing)
                }.padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        HStack {
                            Text(collectionLabel).font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find a wallpaper", text: $search).textFieldStyle(.plain).frame(width: 160)
                        }
                        if section == "Library" { categoryFilters }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 18) {
                            if section == "My videos" {
                                ForEach(store.videos.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { video in videoCard(video) }
                            } else {
                                ForEach(visibleScenes) { scene in sceneCard(scene) }
                            }
                        }
                        if section == "Library" && visibleScenes.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").font(.title).foregroundStyle(accent)
                                Text("No wallpapers found").font(.headline)
                                Text("Try another category or a different search.").foregroundStyle(.secondary)
                                Button("Show all wallpapers") { category = "All"; search = "" }
                                    .buttonStyle(.bordered)
                            }.frame(maxWidth: .infinity).padding(30)
                        }
                        if section == "My videos" && store.videos.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "film.stack").font(.system(size: 36)).foregroundStyle(accent)
                                Text("Bring your favorite moment").font(.headline)
                                Text("Import an MP4 or MOV. Driftwall keeps a local copy\nand loops it silently behind your desktop icons.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                                Button("Choose a video…") { store.importVideo() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).disabled(store.importing)
                            }.frame(maxWidth: .infinity).padding(30)
                        }
                        Text("Made for your Mac. No account. No subscription. All yours.").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 6)
                    }.padding(.bottom, 20)
                }
            }.padding(28)
        }
        .background(Color(red: 0.055, green: 0.068, blue: 0.085))
        .frame(minWidth: 920, minHeight: 650)
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Remove this video from Driftwall?", isPresented: Binding(get: { videoToDelete != nil }, set: { if !$0 { videoToDelete = nil } }), titleVisibility: .visible) {
            Button("Remove Video", role: .destructive) { if let video = videoToDelete { store.removeVideo(video) }; videoToDelete = nil }
        } message: { Text("Only Driftwall’s imported copy will be deleted. Your original file stays where it is.") }
    }
    var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["All"] + Scene.categories, id: \.self) { item in
                    Button { category = item } label: {
                        Text(item).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(category == item ? accent : .secondary)
                            .background(category == item ? accent.opacity(0.09) : .white.opacity(0.04), in: Capsule())
                            .overlay(Capsule().stroke(category == item ? accent.opacity(0.65) : .clear))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Filter by \(item)")
                        .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }.padding(.vertical, 1)
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill").font(.title2).foregroundStyle(accent)
                Text("Driftwall").font(.system(size: 22, weight: .bold, design: .rounded))
            }.padding(.top, 16)
            Text("YOUR DESKTOP, REIMAGINED").font(.system(size: 8, weight: .bold)).tracking(1.7).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                nav("Discover", icon: "square.grid.2x2")
                nav("Library", icon: "square.stack.3d.up")
                nav("My videos", icon: "play.rectangle")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(store.active == nil ? .gray : accent).frame(width: 6, height: 6); Text(store.active == nil ? "NOT PLAYING" : "ON YOUR DESKTOP").font(.system(size: 9, weight: .bold)).tracking(1) }
                Text(store.active == nil ? "Find your atmosphere" : store.activeName).font(.headline)
                Text(store.status).font(.caption).foregroundStyle(.secondary)
                if store.active != nil {
                    HStack {
                        Button { store.togglePause() } label: { Label(store.paused ? "Resume" : "Pause", systemImage: store.paused ? "play.fill" : "pause.fill") }
                        Button { store.stop() } label: { Image(systemName: "stop.fill") }.help("Restore original desktop")
                    }.buttonStyle(.bordered)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Button { settings = true } label: { Label("Preferences", systemImage: "slider.horizontal.3").foregroundStyle(.secondary) }.buttonStyle(.plain)
            Text("FREE. FOREVER.").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(accent.opacity(0.65))
        }.padding(22).frame(width: 210).frame(maxHeight: .infinity).background(.black.opacity(0.2))
    }
    func nav(_ title: String, icon: String) -> some View {
        Button { section = title; search = "" } label: {
            HStack(spacing: 12) { Image(systemName: icon); Text(title); Spacer() }.padding(12)
                .foregroundStyle(section == title ? accent : .secondary)
                .background(section == title ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let scene = selectedScene { ScenePreview(kind: scene.kind, animated: false) }
            else if let video = selectedVideo { VideoPreview(url: store.libraryURL.appendingPathComponent(video.filename)) }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 9) {
                Text(selectedScene != nil ? "GENERATIVE  /  ORIGINAL" : "FROM YOUR LIBRARY").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(accent)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.name(for: store.selected)).font(.system(size: 29, weight: .medium, design: .rounded)).lineLimit(1)
                        Text(selectedScene?.subtitle ?? "A moment worth keeping in motion").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button { store.apply() } label: {
                        Label(store.active == store.selected ? "Apply again" : "Set wallpaper", systemImage: "desktopcomputer").fontWeight(.semibold).padding(.horizontal, 9).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                }
            }.padding(24)
        }.frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    func sceneCard(_ scene: Scene) -> some View {
        Button { store.selected = scene.id } label: {
            VStack(alignment: .leading, spacing: 9) {
                ScenePreview(kind: scene.kind).frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 9))
                HStack { Text(scene.name).font(.system(size: 13, weight: .medium)); Spacer(); if store.active == scene.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) } }
                Text(section == "Library" ? "\(scene.category.uppercased())  ·  LIVE SCENE" : "LIVE SCENE  ·  METAL").font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
            }.padding(9).background(store.selected == scene.id ? .white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(store.selected == scene.id ? accent.opacity(0.65) : .white.opacity(0.07), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("Select \(scene.name)")
    }
    func videoCard(_ video: Video) -> some View {
        Button { store.selected = video.id } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack { LinearGradient(colors: [.indigo.opacity(0.4), .black], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "play.rectangle.fill").font(.largeTitle).foregroundStyle(accent) }.frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 9))
                HStack { Text(video.name).lineLimit(1); Spacer(); if store.active == video.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) } }.font(.system(size: 13, weight: .medium))
                Text("LOCAL VIDEO  ·  LOOPS SILENTLY").font(.system(size: 8)).tracking(1).foregroundStyle(.secondary)
            }.padding(9).overlay(RoundedRectangle(cornerRadius: 12).stroke(store.selected == video.id ? accent.opacity(0.65) : .white.opacity(0.07)))
        }.buttonStyle(.plain).contextMenu { Button("Remove from Library…", role: .destructive) { videoToDelete = video } }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: WallpaperStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Make yourself at home").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Form {
                Section("Playback") {
                    Toggle("Pause on battery power", isOn: $store.batteryPause)
                    Toggle("Pause behind a full-screen app", isOn: $store.fullscreenPause)
                    Toggle("Show on all displays", isOn: $store.allDisplays)
                    Picker("Scene frame rate", selection: $store.fps) { Text("15 fps · efficient").tag(15); Text("30 fps · balanced").tag(30); Text("60 fps · smooth").tag(60) }
                }
                Section("Your Mac") {
                    Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLogin($0) }))
                    Text("Playback pauses when your screen sleeps or your Mac gets too warm. Full-screen detection is best effort. Frame rate applies to original scenes; videos retain their native frame rate.").font(.caption).foregroundStyle(.secondary)
                }
                Section("About Driftwall") {
                    Text("An independent, free live wallpaper app. \(Scene.all.count) original GPU-rendered scenes and your own videos. Close the library to keep playback running; use the menu bar to pause or quit.")
                    Text("Desktop animation only. Lock Screen and screen saver integration are not included. Your system wallpaper is never changed; Stop or Quit reveals it immediately.").foregroundStyle(.secondary)
                    Button("Show video library in Finder") { NSWorkspace.shared.open(store.libraryURL) }
                }
            }.formStyle(.grouped)
        }.padding(24).frame(width: 540, height: 560)
    }
}
