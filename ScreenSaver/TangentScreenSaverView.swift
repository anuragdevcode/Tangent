import AppKit
import ScreenSaver

/// The legacy screen saver bundle's principal class.
///
/// It owns the same `Wallpaper` players as the desktop app and asks the shared
/// configuration which wallpaper belongs to this display. Everything runs
/// inside the screen saver process, so the app does not need to stay open.
@objc(TangentScreenSaverView)
final class TangentScreenSaverView: ScreenSaverView {

    private var wallpaper: Wallpaper?
    private var loadedSignature: String?
    private var configurationStamp: Date?
    private var lastConfigurationCheck = Date.distantPast

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unused")
    }

    deinit {
        teardown()
    }

    override func startAnimation() {
        super.startAnimation()
        reloadWallpaperIfNeeded(force: true)
    }

    override func stopAnimation() {
        super.stopAnimation()
        teardown()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isAnimating {
            reloadWallpaperIfNeeded(force: true)
        }
    }

    override func layout() {
        super.layout()
        wallpaper?.view.frame = bounds
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        // The app may switch wallpapers while a preview is open. Polling the
        // config's modification date is cheap when throttled and keeps the
        // preview honest without an IPC channel.
        let now = Date()
        guard now.timeIntervalSince(lastConfigurationCheck) >= 2 else { return }
        lastConfigurationCheck = now
        reloadWallpaperIfNeeded(force: false)
    }

    // MARK: - Playback

    private func reloadWallpaperIfNeeded(force: Bool) {
        let storage = storage()
        let stamp = (try? FileManager.default
            .attributesOfItem(atPath: storage.configurationURL.path)[.modificationDate]) as? Date

        guard force || stamp != configurationStamp else { return }
        configurationStamp = stamp

        guard let configuration = storage.load(),
              let displayID = currentDisplayID(),
              let config = configuration.wallpaper(forDisplayID: displayID)
        else {
            teardown()
            return
        }

        let signature = [String(displayID), config.typeRaw, config.entry, config.title]
            .joined(separator: "|")
        guard force || signature != loadedSignature || wallpaper == nil else { return }

        prepareLibmpv(path: configuration.libmpvPath)
        teardown()

        guard let player = WallpaperFactory.make(config: config) else { return }
        player.view.frame = bounds
        player.view.autoresizingMask = [.width, .height]
        addSubview(player.view)
        player.setMuted(true)
        player.play()

        wallpaper = player
        loadedSignature = signature
    }

    private func teardown() {
        wallpaper?.pause()
        wallpaper?.view.removeFromSuperview()
        wallpaper?.close()
        wallpaper = nil
        loadedSignature = nil
    }

    // MARK: - Environment

    private func storage() -> ScreenSaverStorage {
        let bundleURL = Bundle(for: TangentScreenSaverView.self).bundleURL
        let home = ScreenSaverStorage.homeDirectory(forSaverBundle: bundleURL)
            ?? FileManager.default.homeDirectoryForCurrentUser
        return ScreenSaverStorage(homeDirectory: home)
    }

    private func currentDisplayID() -> CGDirectDisplayID? {
        if let screen = window?.screen {
            return DisplayIdentity.id(of: screen)
        }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(center, $0.frame, false)
        }) {
            return DisplayIdentity.id(of: screen)
        }
        return NSScreen.main.map(DisplayIdentity.id)
    }

    /// `MPVAPI` resolves its library once, lazily. Point it at the app's own
    /// bundled copy before the first player is created.
    private func prepareLibmpv(path: String?) {
        if let path, FileManager.default.fileExists(atPath: path) {
            setenv("TANGENT_LIBMPV", path, 1)
        } else {
            unsetenv("TANGENT_LIBMPV")
        }
    }
}
