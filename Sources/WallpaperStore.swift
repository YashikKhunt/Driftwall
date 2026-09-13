import AppKit
import SwiftUI
import AVFoundation
import MetalKit
import IOKit.ps
import ServiceManagement
import UniformTypeIdentifiers

struct Video: Identifiable, Codable {
    var id: String
    var name: String
    var filename: String
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WallpaperSurface {
    let window: DesktopWindow
    var renderer: SceneRenderer?
    var metalView: MTKView?
    var player: AVQueuePlayer?
    var looper: AVPlayerLooper?
    var videoObservation: NSKeyValueObservation?
    init(screen: NSScreen) {
        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
    }
    func pause(_ paused: Bool) {
        metalView?.isPaused = paused
        if paused { player?.pause() } else { player?.play() }
    }
    func close() {
        pause(true)
        looper?.disableLooping()
        player?.removeAllItems()
        window.close()
    }
}

@MainActor final class WallpaperStore: ObservableObject {
    @Published var selected = "aurora"
    @Published var active: String? = UserDefaults.standard.string(forKey: "active")
    @Published var videos: [Video] = []
    @Published var paused = false
    @Published var status = "Ready when you are"
    @Published var error: String?
    @Published var importing = false
    @Published var batteryPause = UserDefaults.standard.object(forKey: "batteryPause") as? Bool ?? true { didSet { saveSettings(); refreshPlayback() } }
    @Published var fullscreenPause = UserDefaults.standard.object(forKey: "fullscreenPause") as? Bool ?? true { didSet { saveSettings(); refreshPlayback() } }
    @Published var allDisplays = UserDefaults.standard.object(forKey: "allDisplays") as? Bool ?? true { didSet { saveSettings(); rebuild() } }
    @Published var fps = UserDefaults.standard.object(forKey: "fps") as? Int ?? 30 { didSet { saveSettings(); surfaces.forEach { $0.metalView?.preferredFramesPerSecond = fps } } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var surfaces: [WallpaperSurface] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var asleep = false
    let libraryURL: URL
    var activeName: String { name(for: active ?? "") }
    func name(for id: String) -> String { Scene.all.first { $0.id == id }?.name ?? videos.first { $0.id == id }?.name ?? "No wallpaper" }

    init() {
        libraryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Driftwall/Library", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            let manifest = libraryURL.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                videos = try JSONDecoder().decode([Video].self, from: Data(contentsOf: manifest))
            }
        } catch { self.error = "Could not load your video library: \(error.localizedDescription)" }
        selected = active ?? "aurora"
        let nc = NSWorkspace.shared.notificationCenter
        for notification in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(nc.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.asleep = true; self?.refreshPlayback() }
            })
        }
        for notification in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.asleep = false; self?.refreshPlayback() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshPlayback() } }
        rebuild()
        if CommandLine.arguments.contains("--enable-login") { setLogin(true) }
    }
    func saveSettings() {
        let d = UserDefaults.standard
        d.set(batteryPause, forKey: "batteryPause")
        d.set(fullscreenPause, forKey: "fullscreenPause")
        d.set(allDisplays, forKey: "allDisplays")
        d.set(fps, forKey: "fps")
    }
    func apply() { active = selected; paused = false; UserDefaults.standard.set(active, forKey: "active"); rebuild() }
    func stop() {
        surfaces.forEach { $0.close() }; surfaces.removeAll()
        active = nil; UserDefaults.standard.removeObject(forKey: "active"); status = "Original desktop restored"
    }
    func togglePause() { paused.toggle(); refreshPlayback() }
    func rebuild() {
        surfaces.forEach { $0.close() }; surfaces.removeAll()
        guard let active else { return }
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let surface = WallpaperSurface(screen: screen)
            if let scene = Scene.all.first(where: { $0.id == active }) {
                let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size))
                guard let renderer = SceneRenderer(view: view, kind: scene.kind) else {
                    error = "Your Mac could not initialize the Metal renderer."; stop(); return
                }
                view.preferredFramesPerSecond = fps
                // A bounded render size keeps procedural scenes inexpensive on Retina displays.
                view.autoResizeDrawable = false
                let scale = min(1, 1920 / screen.frame.width)
                view.drawableSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
                surface.renderer = renderer; surface.metalView = view
                surface.window.contentView = view
            } else if let video = videos.first(where: { $0.id == active }) {
                let url = libraryURL.appendingPathComponent(video.filename)
                guard FileManager.default.fileExists(atPath: url.path) else { error = "This video is missing. Import it again."; stop(); return }
                let player = AVQueuePlayer()
                player.isMuted = true
                let item = AVPlayerItem(url: url)
                surface.looper = AVPlayerLooper(player: player, templateItem: item)
                surface.player = player
                surface.videoObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
                    if player.status == .failed {
                        let message = player.error?.localizedDescription ?? "The video could not be played."
                        Task { @MainActor in self?.error = message; self?.stop() }
                    }
                }
                let view = VideoLayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
                view.playerLayer.player = player
                surface.window.contentView = view
            } else { stop(); return }
            surfaces.append(surface)
            surface.window.orderFrontRegardless()
        }
        refreshPlayback()
    }
    func refreshPlayback() {
        guard active != nil else { return }
        var reason: String?
        if paused { reason = "Paused by you" }
        else if asleep { reason = "Paused while the screen sleeps" }
        else if batteryPause && onBattery() { reason = "Paused on battery power" }
        else if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { reason = "Paused to let your Mac cool down" }
        else if fullscreenPause && foregroundCoversDisplay() { reason = "Paused behind a full-screen app" }
        surfaces.forEach { $0.pause(reason != nil) }
        status = reason ?? "Playing on \(surfaces.count) display\(surfaces.count == 1 ? "" : "s")"
    }
    private func onBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return type as String == kIOPSBatteryPowerValue
    }
    private func foregroundCoversDisplay() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder",
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return NSScreen.screens.contains { abs(width - $0.frame.width) < 5 && abs(height - $0.frame.height) < 5 }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { error = "Approve Driftwall in System Settings → General → Login Items." }
        } catch { self.error = "Could not change launch at login: \(error.localizedDescription)" }
    }
    func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.message = "Choose videos to keep in your wallpaper library. Videos play silently and loop."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        importing = true
        Task {
            defer { importing = false }
            for url in urls {
                do {
                    let asset = AVURLAsset(url: url)
                    let playable = try await asset.load(.isPlayable)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let duration = try await asset.load(.duration)
                    guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
                        throw NSError(domain: "Driftwall", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not a playable video."])
                    }
                    let id = UUID().uuidString
                    let filename = id + "." + url.pathExtension
                    let destination = libraryURL.appendingPathComponent(filename)
                    try await Task.detached { try FileManager.default.copyItem(at: url, to: destination) }.value
                    let video = Video(id: id, name: url.deletingPathExtension().lastPathComponent, filename: filename)
                    videos.append(video)
                    do { try saveLibrary() } catch { videos.removeAll { $0.id == id }; try? FileManager.default.removeItem(at: destination); throw error }
                    selected = id
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func removeVideo(_ video: Video) {
        let oldVideos = videos
        videos.removeAll { $0.id == video.id }
        do {
            try saveLibrary()
        } catch { videos = oldVideos; self.error = error.localizedDescription; return }
        if active == video.id { stop() }
        if selected == video.id { selected = "aurora" }
        do { try FileManager.default.removeItem(at: libraryURL.appendingPathComponent(video.filename)) }
        catch { self.error = "Removed from the library, but could not delete the copied file: \(error.localizedDescription)" }
    }
    private func saveLibrary() throws {
        try JSONEncoder().encode(videos).write(to: libraryURL.appendingPathComponent("library.json"), options: .atomic)
    }
}

final class VideoLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
    }
    required init?(coder: NSCoder) { fatalError() }
}
