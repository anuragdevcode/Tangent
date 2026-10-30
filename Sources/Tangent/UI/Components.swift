import AppKit

/// Temporary diagnostics for the UI bring-up. Writes synchronously so a crash
/// or swallowed exception still leaves a trail.
// MARK: - Base views

/// A layer-backed view that re-applies dynamic colors when the effective
/// appearance changes, so the interface follows Light and Dark Mode live.
class ThemedView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyTheme()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Backing layers are created lazily, so the first `applyTheme()` during
        // init usually runs with `layer == nil`. Reapply once we are on screen.
        applyTheme()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    func applyTheme() {}
}

/// Solid window canvas that the vibrancy panes sample.
final class CanvasView: ThemedView {
    override func applyTheme() {
        layer?.backgroundColor = Theme.canvas.cgColor
    }
}

/// Opaque side pane. Used where a material would sample the live wallpaper and
/// change readability as the wallpaper moves.
final class PaneView: ThemedView {
    override func applyTheme() {
        layer?.backgroundColor = Theme.paneFill.cgColor
    }
}

/// The one-pixel separator used between panes and inside cards.
final class HairlineView: ThemedView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }

    override func applyTheme() {
        layer?.backgroundColor = Theme.hairline.cgColor
    }
}

/// Rounded, bordered surface used for cards, grouped rows and panels.
class CardView: ThemedView {

    var radius: CGFloat = Theme.Radius.card {
        didSet { layer?.cornerRadius = radius }
    }
    var fillColor: NSColor = Theme.cardFill {
        didSet { layer?.backgroundColor = fillColor.cgColor }
    }
    var borderColor: NSColor? = Theme.hairline {
        didSet { layer?.borderColor = borderColor?.cgColor }
    }
    var borderWidth: CGFloat = 1 {
        didSet { layer?.borderWidth = borderWidth }
    }
    var castsShadow = false {
        didSet { updateShadow() }
    }
    var shadowStrength: Float = 0.32 {
        didSet { updateShadow() }
    }
    var shadowRadius: CGFloat = 14 {
        didSet { updateShadow() }
    }

    override func applyTheme() {
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderWidth = borderWidth
        layer?.borderColor = borderColor?.cgColor
        updateShadow()
    }

    private func updateShadow() {
        guard let layer else { return }
        layer.masksToBounds = false
        layer.shadowColor = Theme.cardShadow.cgColor
        layer.shadowOpacity = castsShadow ? shadowStrength : 0
        layer.shadowRadius = castsShadow ? shadowRadius : 0
        layer.shadowOffset = NSSize(width: 0, height: -5)
        layer.shadowPath = castsShadow
            ? CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
            : nil
    }

    override func layout() {
        super.layout()
        if castsShadow {
            layer?.shadowPath = CGPath(
                roundedRect: bounds,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        }
    }
}

/// Native blur behind the window. `.behindWindow` lets the desktop bleed
/// through; `.withinWindow` blends with what is already drawn.
final class VisualEffectView: NSVisualEffectView {

    init(
        material: NSVisualEffectView.Material,
        blending: NSVisualEffectView.BlendingMode = .behindWindow,
        emphasized: Bool = false
    ) {
        super.init(frame: .zero)
        self.material = material
        self.blendingMode = blending
        self.state = .followsWindowActiveState
        self.isEmphasized = emphasized
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }
}

/// A flipped document view for scrollable settings pages.
final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Labels

func makeLabel(
    _ text: String,
    font: NSFont = Theme.body,
    color: NSColor = .labelColor,
    lines: Int = 1,
    alignment: NSTextAlignment = .left
) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.maximumNumberOfLines = lines
    field.alignment = alignment
    field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    if lines > 1 {
        field.cell?.wraps = true
        field.cell?.isScrollable = false
    }
    return field
}

func makeWrappingLabel(
    _ text: String,
    font: NSFont = Theme.caption,
    color: NSColor = .secondaryLabelColor
) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = font
    field.textColor = color
    field.maximumNumberOfLines = 0
    field.cell?.wraps = true
    field.cell?.isScrollable = false
    return field
}

func makeSectionHeader(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text.uppercased())
    label.font = Theme.label
    label.textColor = .tertiaryLabelColor
    label.attributedStringValue = NSAttributedString(
        string: text.uppercased(),
        attributes: [
            .font: Theme.label,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 0.6,
        ]
    )
    return label
}

// MARK: - Stack helpers

func vstack(
    _ views: [NSView],
    spacing: CGFloat = Theme.Spacing.small,
    alignment: NSLayoutConstraint.Attribute = .leading
) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = alignment
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func hstack(
    _ views: [NSView],
    spacing: CGFloat = Theme.Spacing.small,
    alignment: NSLayoutConstraint.Attribute = .centerY
) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = alignment
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func flexibleSpacer() -> NSView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return spacer
}

extension NSView {
    /// Pins all four edges of `child` to this view.
    func pin(_ child: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    /// Pins a child to the top, leading and trailing edges, leaving the bottom
    /// free (used for scroll documents whose height is content driven).
    func pinHorizontally(_ child: NSView, top: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchor, constant: top),
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailing),
        ])
    }
}

// MARK: - Symbols

enum Symbols {
    static func image(
        _ name: String,
        pointSize: CGFloat = 13,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    static func view(
        _ name: String,
        pointSize: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        color: NSColor = .secondaryLabelColor
    ) -> NSImageView {
        let view = NSImageView()
        view.image = image(name, pointSize: pointSize, weight: weight)
        view.contentTintColor = color
        view.imageScaling = .scaleProportionallyDown
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

// MARK: - Buttons

/// Borderless, layer-backed button with a native hover fill. Used for pills,
/// toolbar-like actions and icon buttons.
class HoverButton: NSButton {

    enum Style {
        case accent
        case filled
        case outlined
        case borderless
        case quiet
        /// Sits on top of wallpaper artwork, where the window's own control
        /// fill would disappear into bright frames.
        case overlay
        /// Ko-fi's own button colour, so support reads as Ko-fi rather than as
        /// the app's accent.
        case koFi
    }

    var style: Style = .filled {
        didSet { applyStyle() }
    }
    var horizontalPadding: CGFloat = 11

    private(set) var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(
        _ title: String,
        symbol: String? = nil,
        style: Style = .filled,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) {
        super.init(frame: .zero)
        // `NSButton(frame:)` starts with a literal "Button" title; clear it or it
        // shows through icon-only buttons underneath the glyph.
        self.title = title
        self.style = style
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        font = Theme.callout
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        imageHugsTitle = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        contentTintColor = .labelColor

        if let symbol {
            image = Symbols.image(symbol, pointSize: 12, weight: .medium)
        }
        if !title.isEmpty {
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: Theme.callout, .foregroundColor: NSColor.labelColor]
            )
        }
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override var isEnabled: Bool {
        didSet { applyStyle() }
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += horizontalPadding * 2
        size.height = max(size.height, 26)
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        applyStyle(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        applyStyle(animated: true)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(Theme.Radius.control, bounds.height / 2)
    }

    func applyStyle(animated: Bool = false) {
        let background: NSColor
        let foreground: NSColor
        var border: NSColor?

        switch style {
        case .accent:
            background = isHovered
                ? Theme.accent.blended(withFraction: 0.12, of: .white) ?? Theme.accent
                : Theme.accent
            foreground = .white
        case .filled:
            background = isHovered ? Theme.controlFillHover : Theme.controlFill
            foreground = .labelColor
        case .outlined:
            background = isHovered ? Theme.controlFillHover : NSColor.clear
            foreground = .labelColor
            border = Theme.hairline
        case .borderless:
            background = isHovered ? Theme.rowHover : NSColor.clear
            foreground = .secondaryLabelColor
        case .quiet:
            background = isHovered ? Theme.controlFill : NSColor.clear
            foreground = .tertiaryLabelColor
        case .overlay:
            background = NSColor.black.withAlphaComponent(isHovered ? 0.72 : 0.58)
            foreground = .white
        case .koFi:
            background = isHovered
                ? Theme.koFi.blended(withFraction: 0.14, of: .white) ?? Theme.koFi
                : Theme.koFi
            foreground = .white
        }

        var backgroundColor = background
        var titleColor = foreground
        if !isEnabled {
            backgroundColor = background.withAlphaComponent(style == .accent ? 0.4 : 0.5)
            titleColor = foreground.withAlphaComponent(0.55)
        }

        contentTintColor = titleColor
        if !title.isEmpty {
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: font ?? Theme.callout, .foregroundColor: titleColor]
            )
        }

        let changes = {
            self.layer?.backgroundColor = backgroundColor.cgColor
            self.layer?.borderColor = border?.cgColor
        }
        if animated, style != .accent {
            Theme.animate(Theme.hoverDuration, changes: changes)
        } else {
            changes()
        }
        layer?.borderWidth = border == nil ? 0 : 1
    }
}

/// Square icon button used in toolbars and card overlays.
final class IconButton: HoverButton {

    init(
        symbol: String,
        pointSize: CGFloat = 13,
        style: Style = .borderless,
        toolTip: String? = nil,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) {
        super.init("", symbol: symbol, style: style, target: target, action: action)
        self.toolTip = toolTip
        self.setAccessibilityLabel(toolTip ?? symbol)
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        image = Symbols.image(symbol, pointSize: pointSize, weight: .medium)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }
}

// MARK: - Badges and status

/// Small tinted capsule used for wallpaper types and state.
final class BadgeView: ThemedView {

    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let stack = NSStackView()

    private(set) var text: String = ""
    private(set) var tint: NSColor = .secondaryLabelColor
    private var backgroundOverride: NSColor?

    init(text: String = "", symbol: String? = nil, tint: NSColor = .secondaryLabelColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        label.font = Theme.tiny
        label.maximumNumberOfLines = 1
        icon.imageScaling = .scaleProportionallyDown

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            icon.widthAnchor.constraint(equalToConstant: 9),
            icon.heightAnchor.constraint(equalToConstant: 9),
        ])

        configure(text: text, symbol: symbol, tint: tint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func configure(
        text: String,
        symbol: String? = nil,
        tint: NSColor,
        background: NSColor? = nil
    ) {
        self.text = text
        self.tint = tint
        self.backgroundOverride = background
        label.stringValue = text
        label.textColor = tint
        icon.image = symbol.flatMap { Symbols.image($0, pointSize: 9, weight: .semibold) }
        icon.contentTintColor = tint
        icon.isHidden = symbol == nil
        layer?.backgroundColor = (background ?? tint.withAlphaComponent(0.14)).cgColor
        needsLayout = true
    }

    override func applyTheme() {
        layer?.cornerRadius = 6
        layer?.backgroundColor = (backgroundOverride ?? tint.withAlphaComponent(0.14)).cgColor
    }
}

/// Wider status capsule with a leading dot, used for playback state.
final class StatusPillView: ThemedView {

    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private var stack: NSStackView!
    private var tint: NSColor = .secondaryLabelColor

    init(text: String = "", tint: NSColor = .secondaryLabelColor, symbol: String? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // A capsule is a label, not a bar: it must keep its intrinsic width
        // when a stack offers it extra space next to text.
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = Theme.label
        label.maximumNumberOfLines = 1

        stack = hstack([dot, label], spacing: 6)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
        dot.layer?.cornerRadius = 3

        _ = symbol
        configure(text: text, tint: tint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    /// A capsule is as wide as its label. Without an intrinsic size a plain
    /// `NSView` cannot hug its content, so a stack hands it the extra width.
    override var intrinsicContentSize: NSSize {
        let content = stack.fittingSize
        return NSSize(width: content.width + 17, height: content.height + 8)
    }

    func configure(text: String, tint: NSColor) {
        self.tint = tint
        label.stringValue = text
        invalidateIntrinsicContentSize()
        label.textColor = tint
        dot.layer?.backgroundColor = tint.cgColor
        layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
    }

    override func applyTheme() {
        layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
        updateCornerRadius()
    }

    override func layout() {
        super.layout()
        updateCornerRadius()
    }

    /// A capsule uses half the height, not an arbitrarily large radius: Core
    /// Animation's continuous-curve mask misbehaves with huge radii and can
    /// paint a window-sized smear of the layer's background.
    private func updateCornerRadius() {
        layer?.cornerRadius = bounds.height / 2
    }
}

/// Retains a closure for AppKit target/action wiring.
final class ActionTarget: NSObject {
    private let handler: (Any?) -> Void

    init(_ handler: @escaping (Any?) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ sender: Any?) {
        handler(sender)
    }
}

// MARK: - Key cap
/// Rounded keycap used to display a shortcut.
final class KeyCapView: ThemedView {

    private let label = NSTextField(labelWithString: "")

    init(_ text: String) {
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.stringValue = text
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func applyTheme() {
        layer?.cornerRadius = 4
        layer?.backgroundColor = Theme.controlFill.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor
    }
}

// MARK: - Brand mark

/// The Tangent mark: a continuous-radius gradient tile with the sparkles
/// symbol. Drawn in code so the app carries no bitmap assets.
final class BrandMarkView: NSView {

    private let gradient = CAGradientLayer()
    private let icon = NSImageView()

    init(size: CGFloat = 64, symbol: String = "sparkles") {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = size * 0.235
        layer?.masksToBounds = true

        gradient.colors = [
            NSColor.controlAccentColor.blended(withFraction: 0.25, of: .systemTeal)?.cgColor
                ?? NSColor.controlAccentColor.cgColor,
            NSColor.controlAccentColor.blended(withFraction: 0.55, of: .systemPurple)?.cgColor
                ?? NSColor.controlAccentColor.cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.1, y: 1)
        gradient.endPoint = CGPoint(x: 0.9, y: 0)
        layer?.addSublayer(gradient)

        icon.image = Symbols.image(symbol, pointSize: size * 0.52, weight: .regular)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        let inset = bounds.width * 0.24
        icon.frame = bounds.insetBy(dx: inset, dy: inset)
    }
}

// MARK: - Empty state

final class EmptyStateView: NSView {

    private let onAction: (() -> Void)?
    let actionButton: HoverButton?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        actionSymbol: String = "plus",
        action: (() -> Void)? = nil
    ) {
        self.onAction = action
        self.actionButton = actionTitle.map {
            HoverButton($0, symbol: actionSymbol, style: .accent, target: nil, action: nil)
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconBackground = CardView()
        iconBackground.radius = 18
        iconBackground.fillColor = Theme.controlFill
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        let icon = Symbols.view(symbol, pointSize: 22, weight: .regular, color: .secondaryLabelColor)
        iconBackground.addSubview(icon)
        NSLayoutConstraint.activate([
            iconBackground.widthAnchor.constraint(equalToConstant: 58),
            iconBackground.heightAnchor.constraint(equalToConstant: 58),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
        ])

        let titleLabel = makeLabel(title, font: Theme.paneTitle, color: .labelColor, lines: 2, alignment: .center)
        let messageLabel = makeWrappingLabel(message, font: Theme.callout, color: .secondaryLabelColor)
        messageLabel.alignment = .center

        var views: [NSView] = [iconBackground, titleLabel, messageLabel]
        if let button = actionButton {
            button.target = self
            button.action = #selector(actionTapped)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            views.append(button)
        }

        let stack = vstack(views, spacing: 10, alignment: .centerX)
        stack.setCustomSpacing(14, after: iconBackground)
        stack.setCustomSpacing(6, after: titleLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    @objc private func actionTapped() {
        onAction?()
    }
}

// MARK: - Grouped section

/// A titled group of rows, drawn as one rounded card.
final class GroupedSection: NSView {

    private let contentStack: NSStackView

    init(title: String?, rows: [NSView], spacing: CGFloat = 0) {
        contentStack = NSStackView(views: rows)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = spacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let card = CardView()
        card.fillColor = Theme.cardFill
        card.radius = Theme.Radius.card
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        var views: [NSView] = []
        if let title {
            views.append(makeSectionHeader(title))
        }
        views.append(card)
        let outer = vstack(views, spacing: 7)
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }
}

/// A row inside a `GroupedSection`: symbol, title, subtitle and trailing view.
final class SettingsRow: NSView {

    let trailing: NSView?

    init(
        symbol: String?,
        title: String,
        subtitle: String? = nil,
        trailing: NSView? = nil,
        action: (() -> Void)? = nil
    ) {
        self.trailing = trailing
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        var leadingViews: [NSView] = []
        if let symbol {
            let iconBox = CardView()
            iconBox.radius = 6
            iconBox.fillColor = Theme.controlFill
            iconBox.translatesAutoresizingMaskIntoConstraints = false
            let icon = Symbols.view(symbol, pointSize: 12, weight: .medium, color: .secondaryLabelColor)
            iconBox.addSubview(icon)
            NSLayoutConstraint.activate([
                iconBox.widthAnchor.constraint(equalToConstant: 24),
                iconBox.heightAnchor.constraint(equalToConstant: 24),
                icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            ])
            leadingViews.append(iconBox)
        }

        let titleLabel = makeLabel(title, font: Theme.body, color: .labelColor)
        var textViews: [NSView] = [titleLabel]
        if let subtitle {
            textViews.append(makeWrappingLabel(subtitle, font: Theme.caption, color: .secondaryLabelColor))
        }
        let textStack = vstack(textViews, spacing: 2)
        leadingViews.append(textStack)

        var views: [NSView] = leadingViews
        views.append(flexibleSpacer())
        if let trailing { views.append(trailing) }

        let row = hstack(views, spacing: 10)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
        ])

        if let action {
            // The whole row is clickable; controls placed in `trailing` still
            // receive their own clicks through the hit test above.
            let overlay = RowActionButton(action: action)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: topAnchor),
                overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
                overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }
}

/// Transparent button overlay so a whole settings row is clickable.
private final class RowActionButton: NSButton {
    private let handler: () -> Void

    init(action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        self.action = #selector(fire)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    @objc private func fire() { handler() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let switch controls and buttons inside the row receive their clicks.
        guard let hit = super.hitTest(point) else { return nil }
        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            if view is NSControl { return nil }
            candidate = view.superview
        }
        return hit
    }
}
