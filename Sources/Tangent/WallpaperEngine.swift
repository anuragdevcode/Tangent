import AppKit

/// Owns the wallpaper lifecycle across every display.
///
/// Each connected display gets its own desktop-level window and its own player
/// instance, resolved through a `DisplayLayout` so displays can run different
/// wallpapers.
final class WallpaperEngine {

    private struct Entry {
        let window: WallpaperWindow
        let wallpaper: Wallpaper
        /// Pack root, so live control changes only reach the edited pack.
        let rootFolder: String?
    }

    /// Keyed by `CGDirectDisplayID`, so a display keeps its wallpaper when the
    /// screen arrangement changes but that display stays connected.
    private var entries: [CGDirectDisplayID: Entry] = [:]
    private(set) var pauseReasons: Set<PauseReason> = []
    /// Files AVFoundation rejected; they are retried through libmpv.
    private var forcedMPVPaths: Set<String> = []

    /// Called after any state change so the interface can refresh without
    /// polling the engine.
    var onChange: (() -> Void)?

    private(set) var layout = DisplayLayout()

    var isPaused: Bool { !pauseReasons.isEmpty }
    var activeDisplayCount: Int { entries.count }
    var hasWallpaper: Bool { layout.hasPlayableConfig }
    var isMuted: Bool { layout.defaultConfig?.muteAudio ?? true }

    /// Configs currently on screen, in display order. Used by the Displays menu.
    var activeConfigs: [(screen: NSScreen, config: WallpaperConfig)] {
        layout.resolved(for: NSScreen.screens).filter { $0.config.exists }
    }

    /// Frame counters for libmpv-backed wallpapers, used by `--report-frames`
    /// to prove the desktop-level window is actually rendering.
    var mpvFrameReport: (frames: [Int], codecs: [String], errors: [Int]) {
        var frames: [Int] = []
        var codecs: [String] = []
        var errors: [Int] = []
        for entry in entries.values {
            guard let mpv = entry.wallpaper as? MPVWallpaper else { continue }
            frames.append(mpv.renderedFrames)
            codecs.append(mpv.codecName ?? "unknown")
            errors.append(Int(mpv.lastRenderError))
        }
        return (frames, codecs, errors)
    }

    var statusDescription: String {
        let active = activeConfigs
        guard !active.isEmpty else { return "No wallpaper set" }

        let titles = Set(active.map(\.config.title))
        let state = isPaused ? "paused" : "playing"
        let displayText = "\(active.count) display\(active.count == 1 ? "" : "s")"

        if titles.count == 1, let title = titles.first {
            let type = active[0].config.type.displayName
            return "\(title) · \(type) · \(state) · \(displayText)"
        }
        return "\(titles.count) wallpapers · \(state) · \(displayText)"
    }

    func start(layout: DisplayLayout) {
        self.layout = layout
        pauseReasons.removeAll()
        rebuildForScreens()
    }

    /// Applies one wallpaper everywhere; keeps existing per-display overrides,
    /// because a pin is a deliberate choice for that display.
    func start(config: WallpaperConfig) {
        var layout = self.layout
        layout.defaultConfig = config
        start(layout: layout)
    }

    /// Rebuilds every display. Called on launch, when a wallpaper changes, and
    /// whenever the display arrangement changes.
    func rebuildForScreens() {
        teardown()

        for screen in NSScreen.screens {
            let displayID = DisplayIdentity.id(of: screen)
            guard let config = layout.config(for: displayID), config.exists else { continue }
            let forceMPV = forcedMPVPaths.contains(config.entryURL.standardizedFileURL.path)
            guard let wallpaper = WallpaperFactory.make(config: config, forceMPV: forceMPV)
            else { continue }

            let window = WallpaperWindow(screen: screen)
            let host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            wallpaper.view.frame = host.bounds
            wallpaper.view.autoresizingMask = [.width, .height]
            host.addSubview(wallpaper.view)
            window.contentView = host
            window.orderFrontRegardless()

            entries[displayID] = Entry(
                window: window,
                wallpaper: wallpaper,
                rootFolder: config.rootFolder
            )

            if isPaused {
                wallpaper.pause()
            } else {
                wallpaper.play()
            }
        }
        onChange?()
    }

    // MARK: - Layout changes

    func pin(_ config: WallpaperConfig, for displayID: CGDirectDisplayID) {
        layout.pin(config, for: displayID)
        rebuildForScreens()
    }

    func useDefault(for displayID: CGDirectDisplayID) {
        layout.unpin(displayID)
        layout.enable(displayID)
        rebuildForScreens()
    }

    func disable(_ displayID: CGDirectDisplayID) {
        layout.disable(displayID)
        rebuildForScreens()
    }

    func resetOverrides() {
        layout.resetOverrides()
        rebuildForScreens()
    }

    // MARK: - Live control changes

    /// Pushes one property value to the web players showing the edited pack.
    /// Non-web players ignore it.
    func broadcastProperty(name: String, value: JSONValue, root: URL? = nil) {
        for entry in entries.values {
            if let root, entry.rootFolder != root.path { continue }
            (entry.wallpaper as? WebWallpaper)?.setProperty(name: name, value: value)
        }
    }

    /// Mutes or unmutes every player and remembers the choice in the layout.
    /// Preview players never reach this path, so a muted desktop cannot be
    /// unmuted by opening the inspector.
    func setMuted(_ muted: Bool) {
        if layout.defaultConfig != nil {
            layout.defaultConfig?.muteAudio = muted
        }
        for key in layout.pins.keys {
            layout.pins[key]?.muteAudio = muted
        }
        for entry in entries.values {
            entry.wallpaper.setMuted(muted)
        }
        onChange?()
    }

    // MARK: - Playback

    func pause(_ reason: PauseReason = .user) {
        pauseReasons.insert(reason)
        entries.values.forEach { $0.wallpaper.pause() }
        onChange?()
    }

    func resume(_ reason: PauseReason = .user) {
        pauseReasons.remove(reason)
        guard !isPaused else {
            onChange?()
            return
        }
        entries.values.forEach { $0.wallpaper.play() }
        onChange?()
    }

    /// Retries one video with libmpv after AVFoundation reported it unplayable.
    func retryWithMPV(url: URL) {
        forcedMPVPaths.insert(url.standardizedFileURL.path)
        rebuildForScreens()
    }

    func stop() {
        teardown()
        layout = DisplayLayout()
        pauseReasons.removeAll()
        forcedMPVPaths.removeAll()
        onChange?()
    }

    private func teardown() {
        for entry in entries.values {
            entry.wallpaper.close()
            entry.window.orderOut(nil)
            entry.window.close()
        }
        entries.removeAll()
    }
}
