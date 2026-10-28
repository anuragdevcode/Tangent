import AppKit

/// Design tokens for the AppKit interface.
///
/// Everything here maps to system colors, system materials and system fonts so
/// the app follows the user's appearance, accent color and accessibility
/// settings instead of inventing its own palette.
enum Theme {

    enum Radius {
        static let card: CGFloat = 14
        static let preview: CGFloat = 11
        static let control: CGFloat = 8
        static let row: CGFloat = 7
        static let pill: CGFloat = 11
    }

    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let regular: CGFloat = 16
        static let large: CGFloat = 22
        static let section: CGFloat = 28
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
        dark: NSColor(white: 1, alpha: 0.055),
        light: NSColor(white: 0, alpha: 0.035)
    )

    static let cardFillElevated = dynamic(
        dark: NSColor(white: 1, alpha: 0.085),
        light: NSColor(white: 0, alpha: 0.055)
    )

    /// A one-pixel inner edge that defines floating cards against the blur.
    static let hairline = dynamic(
        dark: NSColor(white: 1, alpha: 0.09),
        light: NSColor(white: 0, alpha: 0.075)
    )

    static let controlFill = dynamic(
        dark: NSColor(white: 1, alpha: 0.07),
        light: NSColor(white: 0, alpha: 0.05)
    )

    static let controlFillHover = dynamic(
        dark: NSColor(white: 1, alpha: 0.13),
        light: NSColor(white: 0, alpha: 0.095)
    )

    static let rowHover = dynamic(
        dark: NSColor(white: 1, alpha: 0.055),
        light: NSColor(white: 0, alpha: 0.04)
    )

    static let selectionFill = dynamic(
        dark: NSColor.controlAccentColor.withAlphaComponent(0.22),
        light: NSColor.controlAccentColor.withAlphaComponent(0.15)
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
    static let warning = NSColor.systemOrange
    static let positive = NSColor.systemGreen
    static let secondaryText = NSColor.secondaryLabelColor
    static let tertiaryText = NSColor.tertiaryLabelColor

    static let cardShadow = NSColor.black.withAlphaComponent(0.28)
    static let accentGlow = NSColor.controlAccentColor.withAlphaComponent(0.45)

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

    static let windowTitle = font(22, .bold)
    static let paneTitle = font(17, .semibold)
    static let cardTitle = font(13, .semibold)
    static let body = font(13, .regular)
    static let callout = font(12, .regular)
    static let caption = font(11, .regular)
    static let label = font(11, .medium)
    static let tiny = font(10, .medium)
    static let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let monoSmall = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    // MARK: - Motion

    static let hoverDuration: TimeInterval = 0.18
    static let panelDuration: TimeInterval = 0.24

    /// AppKit's constraint animation. The timing curve is close to the
    /// spring-like feel of system panels without needing a custom animator.
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

    static func springAnimation(keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.damping = 18
        animation.stiffness = 220
        animation.mass = 0.9
        animation.initialVelocity = 0
        animation.duration = animation.settlingDuration
        return animation
    }
}
