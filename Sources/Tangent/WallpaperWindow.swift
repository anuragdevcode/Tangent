import AppKit

/// The desktop host window.
///
/// Some platforms reparent a wallpaper window behind the desktop icons. macOS
/// has no such hierarchy, but it does expose window levels: the desktop picture is drawn at
/// `kCGDesktopWindowLevel` and the icons live at `kCGDesktopIconWindowLevel`.
/// A borderless, click-through window one level above the picture therefore
/// renders behind the icons — no private APIs, no injection, no shell hooks.
///
/// The WindowServer owns the desktop lifecycle, so there are no shell-event
/// hooks or crash recovery to manage.
final class WallpaperWindow: NSWindow {

    /// One level above the static desktop picture, below the icons.
    static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
    )

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = Self.desktopLevel
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // `.stationary` keeps the wallpaper pinned during Mission Control and
        // Space switches; `.canJoinAllSpaces` makes it appear on every Space.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
    }

    // A wallpaper must never take focus from the user's real work.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
