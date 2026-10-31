import AppKit

/// Inspector for the selected wallpaper: a live preview, actions, metadata and
/// the controls that actually map onto the engine.
final class WallpaperInspectorView: NSView {

    private let actions: AppActions
    private let onClose: () -> Void
    private let onToggleFavorite: (Pack) -> Void

    private let preview = LivePreviewView()
    private let titleLabel = makeLabel("No wallpaper selected", font: Theme.paneTitle, lines: 2)
    private let authorLabel = makeLabel("", font: Theme.caption, color: .secondaryLabelColor)
    private let reasonLabel = makeWrappingLabel("", font: Theme.caption, color: .systemOrange)
    private let typeBadge = BadgeView()
    private let activeBadge = BadgeView(text: "Current", symbol: "checkmark", tint: Theme.accent)
    private let favoriteButton = IconButton(symbol: "star", pointSize: 12, style: .quiet, toolTip: "Favorite")
    private let primaryButton = HoverButton("Set for This Screen", symbol: "display", style: .accent)
    private let secondaryButton = HoverButton("Set for All Screens", symbol: "display.2", style: .outlined)
    private let propertiesButton = HoverButton("Wallpaper Properties…", symbol: "slider.horizontal.3", style: .filled)
    private let revealButton = HoverButton("Show in Finder", symbol: "folder", style: .outlined)
    private let removeButton = HoverButton("Remove from Library…", symbol: "minus.circle", style: .borderless)
    private let statusPill = StatusPillView(text: "Live", tint: .systemGreen)
    private let metaStack = NSStackView()
    private let actionStack = NSStackView()

    private var pack: Pack?
    private var snapshot = AppSnapshot()
    private var isFavorite = false
    /// Views that already have a width constraint to the action stack. Rebuilding
    /// the stack on every refresh must not duplicate constraints.
    private var constrainedActionViews: Set<ObjectIdentifier> = []

    init(
        actions: AppActions,
        onClose: @escaping () -> Void,
        onToggleFavorite: @escaping (Pack) -> Void
    ) {
        self.actions = actions
        self.onClose = onClose
        self.onToggleFavorite = onToggleFavorite
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    // MARK: - Layout

    private func build() {
        let header = hstack(
            [
                makeLabel("Inspector", font: Theme.label, color: .secondaryLabelColor),
                flexibleSpacer(),
                favoriteButton,
                closeButton(),
            ],
            spacing: 2
        )

        titleLabel.maximumNumberOfLines = 2
        authorLabel.maximumNumberOfLines = 1

        typeBadge.isHidden = true
        activeBadge.isHidden = true

        let badgeRow = hstack([typeBadge, activeBadge, flexibleSpacer()], spacing: 5)
        let titleBlock = vstack([badgeRow, titleLabel, authorLabel, reasonLabel], spacing: 5)
        reasonLabel.isHidden = true

        primaryButton.target = self
        primaryButton.action = #selector(applyHere)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        secondaryButton.target = self
        secondaryButton.action = #selector(applyAll)
        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        propertiesButton.target = self
        propertiesButton.action = #selector(openProperties)
        propertiesButton.translatesAutoresizingMaskIntoConstraints = false
        propertiesButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        revealButton.target = self
        revealButton.action = #selector(reveal)
        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        removeButton.target = self
        removeButton.action = #selector(remove)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        removeButton.font = Theme.caption

        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite)

        actionStack.orientation = .vertical
        actionStack.alignment = .leading
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        metaStack.orientation = .vertical
        metaStack.alignment = .leading
        metaStack.spacing = 8
        metaStack.translatesAutoresizingMaskIntoConstraints = false

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 10.0 / 16.0).isActive = true

        let statusRow = hstack([statusPill, flexibleSpacer()])
        statusPill.isHidden = true

        let content = vstack(
            [
                header,
                preview,
                titleBlock,
                statusRow,
                actionStack,
                metaStack,
                removeButton,
            ],
            spacing: Theme.Spacing.medium
        )
        content.setCustomSpacing(8, after: header)
        content.setCustomSpacing(8, after: titleBlock)
        content.setCustomSpacing(8, after: statusRow)
        content.setCustomSpacing(16, after: actionStack)
        content.setCustomSpacing(10, after: metaStack)

        for wide in [header, preview, titleBlock, actionStack, metaStack] {
            wide.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        // The inspector is a short, fixed outline. A scroll view here picks up
        // the new scroll-edge glass, which samples the live wallpaper behind the
        // window and tints the whole pane; the stack fits at the minimum height.
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20),
        ])
        content.setContentHuggingPriority(.defaultHigh, for: .vertical)

        updateContent()
    }

    private func closeButton() -> NSButton {
        let button = IconButton(
            symbol: "sidebar.trailing",
            pointSize: 12,
            style: .quiet,
            toolTip: "Hide Inspector",
            target: self,
            action: #selector(closeTapped)
        )
        return button
    }

    // MARK: - Content

    func update(pack: Pack?, snapshot: AppSnapshot, isFavorite: Bool) {
        // Identity, not just the folder: two files can live in one folder and
        // both must show their own name, preview and state.
        let previous = self.pack
        let changed = previous?.id != pack?.id
            || previous?.entryURL?.standardizedFileURL != pack?.entryURL?.standardizedFileURL
        self.pack = pack
        self.snapshot = snapshot
        self.isFavorite = isFavorite
        if changed {
            preview.show(pack: pack)
        }
        updateContent()
    }

    private func updateContent() {
        guard let pack else {
            titleLabel.stringValue = "No wallpaper selected"
            authorLabel.stringValue = "Choose a wallpaper to inspect it."
            authorLabel.isHidden = false
            typeBadge.isHidden = true
            activeBadge.isHidden = true
            reasonLabel.isHidden = true
            preview.show(pack: nil)
            statusPill.isHidden = true
            primaryButton.isEnabled = false
            secondaryButton.isEnabled = false
            propertiesButton.isHidden = true
            revealButton.isEnabled = false
            removeButton.isEnabled = false
            favoriteButton.isHidden = true
            setMetaRows([])
            setActionRows([primaryButton, secondaryButton])
            return
        }

        favoriteButton.isHidden = false
        favoriteButton.image = Symbols.image(
            isFavorite ? "star.fill" : "star",
            pointSize: 12,
            weight: .medium
        )
        favoriteButton.contentTintColor = isFavorite ? .systemYellow : .tertiaryLabelColor

        titleLabel.stringValue = pack.info.title

        // No author line when the pack does not name one: the type badge above
        // the title already says "Video", "Web" or similar.
        if let author = pack.info.author, !author.isEmpty {
            authorLabel.stringValue = "by \(author)"
            authorLabel.isHidden = false
        } else {
            authorLabel.stringValue = ""
            authorLabel.isHidden = true
        }

        typeBadge.isHidden = false
        typeBadge.configure(
            text: pack.info.type.displayName,
            symbol: pack.info.type.glyph,
            tint: pack.typeTint
        )

        let isShowing = pack.isShowing(in: snapshot)
        activeBadge.isHidden = !isShowing

        if let reason = pack.unsupportedReason {
            reasonLabel.stringValue = reason
            reasonLabel.isHidden = false
        } else {
            reasonLabel.isHidden = true
        }

        // The paused state belongs to the running wallpaper. Announcing it next
        // to a wallpaper that is not on screen reads as if this pack were the
        // paused one, so only surface it while the pack is actually applied.
        statusPill.isHidden = !(isShowing && snapshot.isPaused)
        if isShowing, snapshot.isPaused {
            statusPill.configure(text: "Paused", tint: .systemOrange)
        }

        let playable = pack.unsupportedReason == nil
        primaryButton.isEnabled = playable
        secondaryButton.isEnabled = playable
        revealButton.isEnabled = true
        removeButton.isEnabled = true

        let hasProperties = !PropertyStore.shared.controls(forRoot: pack.folder).isEmpty
        propertiesButton.isHidden = !hasProperties

        var actionRows: [NSView] = [primaryButton, secondaryButton]
        if hasProperties { actionRows.append(propertiesButton) }
        setActionRows(actionRows)

        var rows: [(String, String)] = [
            ("Type", pack.info.type.displayName),
            ("Size", Format.size(of: pack)),
            ("Version", pack.info.version > 0 ? "\(pack.info.version)" : "—"),
        ]
        if let license = pack.info.license, !license.isEmpty {
            rows.append(("License", license))
        }
        if !pack.info.tags.isEmpty {
            rows.append(("Tags", pack.info.tags.joined(separator: ", ")))
        }
        rows.append(("Location", Format.relativePath(pack.libraryEntry)))
        setMetaRows(rows)

        if pack.info.type == .video || pack.info.type == .gif || pack.info.type == .picture {
            preview.setLiveAvailable(true)
        } else {
            preview.setLiveAvailable(true)
        }
    }

    private func setActionRows(_ rows: [NSView]) {
        for view in actionStack.arrangedSubviews {
            actionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in rows + [revealButton] {
            actionStack.addArrangedSubview(row)
            let identifier = ObjectIdentifier(row)
            if !constrainedActionViews.contains(identifier) {
                constrainedActionViews.insert(identifier)
                row.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true
            }
        }
    }

    private func setMetaRows(_ rows: [(String, String)]) {
        for view in metaStack.arrangedSubviews {
            metaStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !rows.isEmpty else { return }

        metaStack.addArrangedSubview(makeSectionHeader("Details"))
        for (key, value) in rows {
            let keyLabel = makeLabel(key, font: Theme.label, color: .secondaryLabelColor)
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            keyLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let valueLabel = makeWrappingLabel(value, font: Theme.caption, color: .labelColor)
            valueLabel.isSelectable = key == "Location"
            valueLabel.lineBreakMode = key == "Location" ? .byTruncatingMiddle : .byWordWrapping
            valueLabel.maximumNumberOfLines = key == "Location" ? 2 : 0

            let row = hstack([keyLabel, valueLabel], spacing: 8, alignment: .top)
            metaStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: metaStack.widthAnchor).isActive = true
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() { onClose() }

    @objc private func toggleFavorite() {
        guard let pack else { return }
        onToggleFavorite(pack)
    }

    @objc private func applyHere() {
        guard let pack else { return }
        preview.pause()
        actions.setForThisScreen(pack)
    }

    @objc private func applyAll() {
        guard let pack else { return }
        preview.pause()
        actions.applyToAllScreens(pack)
    }

    @objc private func openProperties() {
        actions.openProperties(pack)
    }

    @objc private func reveal() {
        guard let pack else { return }
        actions.reveal(pack)
    }

    @objc private func remove() {
        guard let pack else { return }
        actions.removeFromLibrary(pack)
    }

    /// Space in the gallery toggles the inspector preview.
    func togglePreview() {
        preview.toggle()
    }

    func stopPreview() {
        preview.stop()
    }
}

// MARK: - Live preview

/// Plays a muted copy of the selected wallpaper inside the inspector. This is
/// the same player stack used behind the desktop, so what you preview is what
/// gets applied.
final class LivePreviewView: NSView {

    private let imageView = NSImageView()
    private let surface = NSView()
    private let playButton = HoverButton("Preview", symbol: "play.fill", style: .overlay)
    private let liveBadge = BadgeView(text: "Live Preview", symbol: "circle.fill", tint: .white)
    private let emptyIcon = Symbols.view("photo.on.rectangle.angled", pointSize: 22, color: .tertiaryLabelColor)
    private let emptyLabel = makeLabel(
        "Select a wallpaper",
        font: Theme.caption,
        color: .tertiaryLabelColor
    )

    private var wallpaper: Wallpaper?
    private var pack: Pack?
    private var currentID: String?
    private var isLive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Theme.Radius.preview
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.previewPlaceholder.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        pin(imageView)

        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        pin(surface)

        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        liveBadge.isHidden = true
        liveBadge.configure(
            text: "Live Preview",
            symbol: "circle.fill",
            tint: .white,
            background: NSColor.black.withAlphaComponent(0.55)
        )
        addSubview(liveBadge)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.target = self
        playButton.action = #selector(toggleTapped)
        // Fixed size: the label flips between "Preview" and "Pause", and a
        // width that follows the current title makes the pill jump on click.
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 92),
            playButton.heightAnchor.constraint(equalToConstant: 26),
        ])
        addSubview(playButton)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        let emptyStack = vstack([emptyIcon, emptyLabel], spacing: 6)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyStack)

        NSLayoutConstraint.activate([
            liveBadge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            playButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            emptyStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyIcon.widthAnchor.constraint(equalToConstant: 30),
            emptyIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.previewPlaceholder.cgColor
    }

    func show(pack: Pack?) {
        stop()
        self.pack = pack
        let identifier = pack?.id
        currentID = identifier
        imageView.image = nil
        playButton.isHidden = pack == nil
        liveBadge.isHidden = true
        emptyIcon.isHidden = pack != nil
        emptyLabel.isHidden = pack != nil
        setLiveAvailable(pack != nil)

        guard let pack else { return }
        Task { [weak self] in
            let image = await ThumbnailProvider.shared.thumbnail(for: pack)
            await MainActor.run {
                guard let self, self.currentID == identifier else { return }
                self.imageView.image = image
                self.emptyIcon.isHidden = image != nil
                self.emptyLabel.isHidden = image != nil
            }
        }
    }

    func setLiveAvailable(_ available: Bool) {
        playButton.isHidden = !available || pack == nil
    }

    @objc private func toggleTapped() {
        toggle()
    }

    func toggle() {
        if isLive {
            pause()
        } else {
            start()
        }
    }

    private func start() {
        guard let pack else { return }
        guard let config = WallpaperConfig(pack: pack) else { return }

        var muted = config
        muted.muteAudio = true
        guard let wallpaper = WallpaperFactory.make(config: muted) else { return }

        wallpaper.setMuted(true)
        wallpaper.view.frame = surface.bounds
        wallpaper.view.autoresizingMask = [.width, .height]
        surface.addSubview(wallpaper.view)
        wallpaper.play()

        self.wallpaper = wallpaper
        isLive = true
        liveBadge.isHidden = false
        playButton.title = "Pause"
        playButton.image = Symbols.image("pause.fill", pointSize: 10, weight: .semibold)
        playButton.applyStyle()
    }

    func pause() {
        wallpaper?.pause()
        isLive = false
        liveBadge.isHidden = true
        playButton.title = "Preview"
        playButton.image = Symbols.image("play.fill", pointSize: 10, weight: .semibold)
        playButton.applyStyle()
    }

    func stop() {
        wallpaper?.close()
        wallpaper?.view.removeFromSuperview()
        wallpaper = nil
        isLive = false
        liveBadge.isHidden = true
        playButton.title = "Preview"
        playButton.image = Symbols.image("play.fill", pointSize: 10, weight: .semibold)
        playButton.applyStyle()
    }
}
