import AppKit

/// Design tokens for the AppKit interface.
///
/// Everything here maps to system colors, system materials and system fonts so
/// the app follows the user's appearance, accent color and accessibility
/// settings instead of inventing its own palette.
enum Theme {

    enum Radius {
        static let card: CGFloat = 10
        static let preview: CGFloat = 8
        static let control: CGFloat = 6
        static let row: CGFloat = 6
        static let pill: CGFloat = 6
    }

    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let regular: CGFloat = 16
        static let large: CGFloat = 24
        static let section: CGFloat = 32
    }

    // MARK: - Colors

    /// Opaque window canvas. The panes sample this with `.withinWindow`
    /// materials, so a live wallpaper behind the window never tints the UI.
    static let canvas = dynamic(
        dark: NSColor(white: 0.11, alpha: 1),
        light: NSColor(white: 0.965, alpha: 1)
    )

    /// Solid inspector pane, a hair lighter than the canvas so the divider reads
    /// without a second material layer.
    static let paneFill = dynamic(
        dark: NSColor(white: 0.135, alpha: 1),
        light: NSColor(white: 0.98, alpha: 1)
    )

    /// Card fills sit on top of window material and stay legible in both
    /// appearances without looking like opaque panels.
    static let cardFill = dynamic(
        dark: NSColor(white: 1, alpha: 0.05),
        light: NSColor(white: 0, alpha: 0.035)
    )

    static let cardFillElevated = dynamic(
        dark: NSColor(white: 1, alpha: 0.075),
        light: NSColor(white: 0, alpha: 0.055)
    )

    /// A one-pixel edge that defines grouped rows against the blur.
    static let hairline = dynamic(
        dark: NSColor(white: 1, alpha: 0.08),
        light: NSColor(white: 0, alpha: 0.075)
    )

    static let controlFill = dynamic(
        dark: NSColor(white: 1, alpha: 0.07),
        light: NSColor(white: 0, alpha: 0.05)
    )

    static let controlFillHover = dynamic(
        dark: NSColor(white: 1, alpha: 0.12),
        light: NSColor(white: 0, alpha: 0.09)
    )

    static let rowHover = dynamic(
        dark: NSColor(white: 1, alpha: 0.05),
        light: NSColor(white: 0, alpha: 0.04)
    )

    static let selectionFill = dynamic(
        dark: NSColor.controlAccentColor.withAlphaComponent(0.18),
        light: NSColor.controlAccentColor.withAlphaComponent(0.13)
    )

    static let sidebarFill = dynamic(
        dark: NSColor(white: 0.11, alpha: 0.30),
        light: NSColor(white: 1, alpha: 0.28)
    )

    static let previewPlaceholder = dynamic(
        dark: NSColor(white: 0.085, alpha: 1),
        light: NSColor(white: 0.92, alpha: 1)
    )

    static let insetPanel = dynamic(
        dark: NSColor(white: 0, alpha: 0.12),
        light: NSColor(white: 0.96, alpha: 0.6)
    )

    static let accent = NSColor.controlAccentColor
    /// Ko-fi's brand blue. Kept as a token for the support window and its
    /// self-test; the About button itself uses the quiet outlined style.
    static let koFi = NSColor(srgbRed: 0.161, green: 0.671, blue: 0.878, alpha: 1)
    static let warning = NSColor.systemOrange
    static let positive = NSColor.systemGreen
    static let secondaryText = NSColor.secondaryLabelColor
    static let tertiaryText = NSColor.tertiaryLabelColor

    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }

    // MARK: - Type

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Page-level heading. Size carries the hierarchy; weight stays moderate so
    /// the window does not read like a landing page.
    static let windowTitle = font(20, .medium)
    static let paneTitle = font(15, .semibold)
    static let cardTitle = font(13, .medium)
    static let body = font(13, .regular)
    static let callout = font(12, .regular)
    static let caption = font(11, .regular)
    static let label = font(11, .regular)
    static let tiny = font(10, .regular)
    static let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let monoSmall = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    // MARK: - Motion

    static let hoverDuration: TimeInterval = 0.16
    static let panelDuration: TimeInterval = 0.2

    /// AppKit's constraint animation, using a plain ease so panels settle
    /// instead of bouncing.
    static func animate(
        _ duration: TimeInterval = panelDuration,
        changes: () -> Void,
        completion: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            changes()
        } completionHandler: {
            completion?()
        }
    }
}
