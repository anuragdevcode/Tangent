import AppKit
import Foundation

/// Persisted wallpaper selection.
///
/// A pack-aware selection that remembers the pack root, so its control file
/// can be resolved later.
struct WallpaperConfig: Codable, Equatable {
    var typeRaw: String
    var entry: String
    var rootFolder: String?
    var title: String
    var muteAudio: Bool = true

    var type: WallpaperType { WallpaperType(raw: typeRaw) }

    var entryURL: URL {
        if entry.hasPrefix("http://") || entry.hasPrefix("https://") {
            return URL(string: entry) ?? URL(fileURLWithPath: entry)
        }
        return URL(fileURLWithPath: entry)
    }

    var root: URL? {
        guard let rootFolder else { return nil }
        return URL(fileURLWithPath: rootFolder)
    }

    var isRemote: Bool {
        entry.hasPrefix("http://") || entry.hasPrefix("https://")
    }

    var exists: Bool {
        if isRemote { return true }
        return FileManager.default.fileExists(atPath: entry)
    }

    init(typeRaw: String, entry: String, rootFolder: String?, title: String, muteAudio: Bool = true) {
        self.typeRaw = typeRaw
        self.entry = entry
        self.rootFolder = rootFolder
        self.title = title
        self.muteAudio = muteAudio
    }

    /// Fails when the pack has no playable entry point, so the caller can show
    /// a real reason instead of persisting a broken selection.
    init?(pack: Pack) {
        guard let entryURL = pack.entryURL else { return nil }
        self.init(
            typeRaw: pack.info.type.rawValue,
            entry: entryURL.absoluteString.hasPrefix("http")
                ? entryURL.absoluteString
                : entryURL.path,
            rootFolder: pack.folder.path,
            title: pack.info.title
        )
    }
}

/// A wallpaper player.
///
/// A wallpaper owns an `NSView` that the engine hands to a desktop-level
/// `NSWindow`, which is how it is embedded behind the desktop icons.
protocol Wallpaper: AnyObject {
    var type: WallpaperType { get }
    var view: NSView { get }
    var isLoaded: Bool { get }
    func play()
    func pause()
    func close()
    func setMuted(_ muted: Bool)
}

/// Maps a library entry to a player implementation.
enum WallpaperFactory {
    /// `forceMPV` is set after AVFoundation rejected a file, so the retry uses
    /// libmpv even when the container looked AVFoundation-compatible.
    static func make(config: WallpaperConfig, forceMPV: Bool = false) -> Wallpaper? {
        switch config.type {
        case .web, .webaudio, .url:
            let controls = config.root.map { PropertyStore.shared.controls(forRoot: $0) } ?? []
            return WebWallpaper(
                entry: config.entryURL,
                root: config.root,
                controls: controls,
                title: config.title,
                type: config.type
            )

        case .video:
            guard !config.isRemote else { return nil }
            if forceMPV || VideoRouting.backend(for: config.entryURL) == .mpv {
                return MPVWallpaper(url: config.entryURL, muted: config.muteAudio)
            }
            return VideoWallpaper(url: config.entryURL, muted: config.muteAudio)

        case .gif, .picture:
            return ImageWallpaper(url: config.entryURL, type: config.type)

        case .app, .bizhawk, .unity, .unityaudio, .godot, .videostream, .unknown:
            return nil
        }
    }
}

/// Layer-backed host for AVPlayerLayer, keeping the layer sized to the view.
final class LayerHostView: NSView {
    private let hosted: CALayer

    init(hosting hosted: CALayer, backgroundColor: NSColor = .black) {
        self.hosted = hosted
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.addSublayer(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }
}
