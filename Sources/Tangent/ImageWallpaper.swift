import AppKit

/// Static image and animated GIF wallpapers (`picture` and `gif` types).
///
/// `NSImageView.animates` handles GIF and APNG frame timing natively, which is
/// why no web view is needed for these two types.
final class ImageWallpaper: Wallpaper {
    let type: WallpaperType
    let view: NSView
    private(set) var isLoaded = false

    private let imageView: NSImageView

    init?(url: URL, type: WallpaperType) {
        guard let image = NSImage(contentsOf: url) else { return nil }
        self.type = type

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        imageView = NSImageView(frame: .zero)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.animates = true
        container.addSubview(imageView)

        view = container
        isLoaded = true
    }

    func play() {
        imageView.animates = true
    }

    func pause() {
        imageView.animates = false
    }

    /// Images and GIFs have no audio track.
    func setMuted(_ muted: Bool) {
        _ = muted
    }

    func close() {
        imageView.animates = false
        imageView.image = nil
        view.removeFromSuperview()
        isLoaded = false
    }
}
