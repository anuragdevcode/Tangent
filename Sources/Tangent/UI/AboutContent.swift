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
        ExternalLink.open(url)
    }
}

/// Shared About content used by the About window, the Settings pane and the
/// About page in the main window.
enum AboutContent {

    static func mark(size: CGFloat = 64) -> NSView {
        BrandMarkView(size: size)
    }

    static func titleBlock() -> NSView {
        let title = makeLabel("Tangent", font: Theme.font(17, .semibold))
        let version = makeLabel(
            "Version \(Format.version())",
            font: Theme.caption,
            color: .tertiaryLabelColor
        )
        let tagline = makeLabel(
            "Wallpaper engine for macOS",
            font: Theme.callout,
            color: .secondaryLabelColor
        )
        return vstack([title, version, tagline], spacing: 2)
    }

    static func blurb() -> NSTextField {
        let label = makeWrappingLabel(
            "A native wallpaper engine for Apple Silicon. Tangent plays video, web, GIF and "
            + "image wallpapers behind the desktop icons, with per-display assignments, "
            + "playback rules and global shortcuts.",
            font: Theme.callout,
            color: .secondaryLabelColor
        )
        return label
    }

    static func primaryActions() -> NSView {
        let support = KoFiSupportButton()
        let github = LinkButton(
            "View on GitHub",
            symbol: "arrow.up.right.square",
            style: .outlined,
            url: TangentLinks.repository
        )
        return hstack([support, github], spacing: 8)
    }

    static func licenseLine() -> NSView {
        let label = makeLabel(
            "GPL-3.0 · © 2026 Tangent contributors",
            font: Theme.caption,
            color: .tertiaryLabelColor
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

    /// Key/value metadata used in About and Settings. Hardware facts come from
    /// the same `DiagnosticsCollector` as bug reports, so the two never drift.
    static func details() -> NSView {
        let diagnostics = DiagnosticsCollector().collect()
        let rows: [(String, String)] = [
            ("Version", "\(diagnostics.appVersion) (\(diagnostics.buildNumber))"),
            ("macOS", diagnostics.shortMacOSVersion),
            ("Hardware", diagnostics.hardwareDescription),
            ("Architecture", diagnostics.architectureDescription),
            ("Compatibility", "macOS 13.0 or later"),
            ("Video", "AVFoundation + libmpv"),
            ("libmpv", Format.libmpv),
        ]

        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 4
        grid.translatesAutoresizingMaskIntoConstraints = false
        for (key, value) in rows {
            let keyLabel = makeLabel(key, font: Theme.label, color: .secondaryLabelColor)
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            keyLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let valueLabel = makeLabel(value, font: Theme.caption, color: .labelColor)
            valueLabel.isSelectable = true
            let row = hstack([keyLabel, valueLabel], spacing: 12)
            grid.addArrangedSubview(row)
        }
        return grid
    }
}

// MARK: - Small layout helpers

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
