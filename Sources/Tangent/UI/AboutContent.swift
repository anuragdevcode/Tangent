import AppKit

/// Opens a URL and remembers it, so link buttons can be created without
/// threading targets through every view builder.
final class LinkButton: HoverButton {

    let url: URL

    init(
        _ title: String,
        symbol: String? = nil,
        style: Style = .outlined,
        url: URL
    ) {
        self.url = url
        super.init(title, symbol: symbol, style: style, target: nil, action: nil)
        target = self
        action = #selector(open)
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    @objc private func open() {
        NSWorkspace.shared.open(url)
    }
}

/// Shared About content used by the About window, the Settings pane and the
/// About page in the main window.
enum AboutContent {

    static func mark(size: CGFloat = 84) -> NSView {
        BrandMarkView(size: size)
    }

    static func titleBlock(centered: Bool = true) -> NSView {
        let alignment: NSTextAlignment = centered ? .center : .left
        let title = makeLabel("Tangent", font: Theme.font(26, .bold), alignment: alignment)
        let tagline = makeLabel(
            "Live wallpapers, native to macOS.",
            font: Theme.body,
            color: .secondaryLabelColor,
            alignment: alignment
        )
        let version = BadgeView(
            text: "Version \(Format.version())",
            symbol: "checkmark.seal",
            tint: Theme.accent
        )
        let versionRow = centered ? centeredRow([version]) : hstack([version])
        let stack = vstack([title, tagline, versionRow], spacing: 5, alignment: centered ? .centerX : .leading)
        stack.setCustomSpacing(10, after: tagline)
        return stack
    }

    static func blurb(centered: Bool = true) -> NSTextField {
        let label = makeWrappingLabel(
            "A native, open-source wallpaper engine for Apple Silicon. Tangent renders video, "
            + "web, GIF and image wallpapers behind the desktop icons, with per-display "
            + "assignments, playback rules and global shortcuts.",
            font: Theme.callout,
            color: .secondaryLabelColor
        )
        label.alignment = centered ? .center : .left
        return label
    }

    static func primaryActions() -> NSView {
        let support = LinkButton(
            "Buy Me a Coffee",
            symbol: "cup.and.saucer.fill",
            style: .accent,
            url: TangentLinks.support
        )
        let github = LinkButton(
            "View on GitHub",
            symbol: "arrow.up.right.square",
            style: .outlined,
            url: TangentLinks.repository
        )
        return centeredRow([support, github], spacing: 10)
    }

    static func licenseLine(centered: Bool = true) -> NSView {
        let label = makeLabel(
            "GPL-3.0 · © 2026 Tangent contributors",
            font: Theme.caption,
            color: .tertiaryLabelColor,
            alignment: centered ? .center : .left
        )
        let license = LinkButton(
            "License",
            symbol: "doc.text",
            style: .borderless,
            url: TangentLinks.license
        )
        license.font = Theme.caption
        license.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let row = hstack([label, inflexibleSpacer(), license], spacing: 8)
        return row
    }

    /// Key/value metadata used in About and Settings.
    static func details() -> NSView {
        let rows: [(String, String)] = [
            ("Version", Format.version()),
            ("Bundle", Bundle.main.bundleIdentifier ?? "app.tangent.wallpaper"),
            ("Architecture", Format.architecture),
            ("Minimum macOS", "13.0"),
            ("Video", "AVFoundation + libmpv"),
            ("libmpv", Format.libmpv),
        ]

        let grid = NSGridView()
        grid.rowSpacing = 7
        grid.columnSpacing = 22
        for (key, value) in rows {
            let keyLabel = makeLabel(key, font: Theme.label, color: .secondaryLabelColor)
            let valueLabel = makeLabel(value, font: Theme.caption, color: .labelColor)
            valueLabel.isSelectable = true
            grid.addRow(with: [keyLabel, valueLabel])
        }
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    static func supportCard(compact: Bool = false) -> NSView {
        let card = CardView()
        card.fillColor = Theme.cardFill
        card.radius = Theme.Radius.card
        card.translatesAutoresizingMaskIntoConstraints = false

        let heart = CardView()
        heart.radius = 10
        heart.fillColor = NSColor.systemPink.withAlphaComponent(0.14)
        heart.translatesAutoresizingMaskIntoConstraints = false
        let heartIcon = Symbols.view("heart.fill", pointSize: 18, weight: .medium, color: .systemPink)
        heart.addSubview(heartIcon)
        NSLayoutConstraint.activate([
            heart.widthAnchor.constraint(equalToConstant: 42),
            heart.heightAnchor.constraint(equalToConstant: 42),
            heartIcon.centerXAnchor.constraint(equalTo: heart.centerXAnchor),
            heartIcon.centerYAnchor.constraint(equalTo: heart.centerYAnchor),
        ])

        let title = makeLabel("Support Tangent", font: Theme.cardTitle)
        let message = makeWrappingLabel(
            compact
                ? "Free and open source. If Tangent improves your desktop, you can buy the developer a coffee."
                : "Tangent is free and open source. If it makes your desktop better, you can support "
                    + "development with a coffee — it directly funds new backends and polish.",
            font: Theme.caption,
            color: .secondaryLabelColor
        )
        let text = vstack([title, message], spacing: 3)

        let coffee = LinkButton(
            "Buy Me a Coffee",
            symbol: "cup.and.saucer.fill",
            style: .accent,
            url: TangentLinks.support
        )
        coffee.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let content: NSView
        if compact {
            let row = hstack([heart, text, inflexibleSpacer(), coffee], spacing: 12)
            content = row
        } else {
            let row = hstack([heart, text], spacing: 12)
            content = vstack([row, coffee], spacing: 12)
        }

        card.pin(content, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    /// Full page for the main window and Settings.
    static func page(centered: Bool = true) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [
            centeredRow([mark()]),
            titleBlock(centered: centered),
            blurb(centered: centered),
            primaryActions(),
            spacing(14),
            supportCard(),
            spacing(6),
            details(),
            spacing(10),
            licenseLine(centered: centered),
        ]
        if !centered {
            views[0] = hstack([mark(size: 64), titleBlock(centered: false)], spacing: 16)
            views.remove(at: 1)
        }

        let stack = vstack(views, spacing: Theme.Spacing.medium, alignment: centered ? .centerX : .leading)
        stack.setCustomSpacing(18, after: views[0])
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}

// MARK: - Small layout helpers

func centeredRow(_ views: [NSView], spacing: CGFloat = 8) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    let stack = hstack(views, spacing: spacing)
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: container.topAnchor),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
    ])
    return container
}

func inflexibleSpacer() -> NSView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
    return spacer
}

func spacing(_ height: CGFloat) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: height).isActive = true
    return view
}
