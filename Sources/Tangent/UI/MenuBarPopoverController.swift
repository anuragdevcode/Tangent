import AppKit

/// The menu bar popover: the everyday surface for the engine.
///
/// It shows what is on the desktop, lets the user pause or resume, change the
/// wallpaper, mute audio and jump to the rest of the app. Every control maps to
/// an engine operation that already exists.
final class MenuBarPopoverController: NSViewController {

    private let actions: AppActions
    private let popover = NSPopover()

    private var snapshot = AppSnapshot()
    private var targets: [ActionTarget] = []

    private let preview = PopoverPreviewView()
    private let statePill = StatusPillView(text: "Off", tint: .secondaryLabelColor)
    private let playButton = HoverButton("Play", symbol: "play.fill", style: .accent)
    private let nextButton = IconButton(
        symbol: "forward.end.fill",
        pointSize: 12,
        style: .filled,
        toolTip: "Next Wallpaper"
    )
    private let propertiesButton = IconButton(
        symbol: "slider.horizontal.3",
        pointSize: 12,
        style: .filled,
        toolTip: "Wallpaper Properties"
    )
    private let displaysStack = NSStackView()
    private var widthConstraint: NSLayoutConstraint!
    private var contentStack: NSStackView!
    private let pauseSwitch = NSSwitch()
    private let muteSwitch = NSSwitch()
    private let desktopIconsSwitch = NSSwitch()
    private var pauseRow: SettingsRow!
    private var desktopIconsRow: SettingsRow!
    private let updateNotice = HoverButton(
        "",
        symbol: "arrow.down.circle.fill",
        style: .borderless
    )

    init(actions: AppActions) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        popover.contentViewController = self
        popover.behavior = .transient
        popover.animates = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func loadView() {
        let root = VisualEffectView(material: .popover, blending: .behindWindow)
        root.translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = root.widthAnchor.constraint(equalToConstant: 340)
        widthConstraint.isActive = true
        view = root

        let header = hstack(
            [
                BrandMarkView(size: 22),
                makeLabel("Tangent", font: Theme.font(13, .semibold)),
                flexibleSpacer(),
                libraryButton(),
                statePill,
            ],
            spacing: 8
        )

        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)

        playButton.target = self
        playButton.action = #selector(togglePause)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        nextButton.target = self
        nextButton.action = #selector(nextWallpaper)
        propertiesButton.target = self
        propertiesButton.action = #selector(openProperties)
        let actionRow = hstack([playButton, nextButton, propertiesButton], spacing: 6)

        let displaysHeader = hstack(
            [makeSectionHeader("Displays"), flexibleSpacer(), manageDisplaysButton()],
            spacing: 6
        )

        displaysStack.orientation = .vertical
        displaysStack.alignment = .leading
        displaysStack.spacing = 1
        displaysStack.translatesAutoresizingMaskIntoConstraints = false

        let displayCard = CardView()
        displayCard.fillColor = Theme.cardFill
        displayCard.translatesAutoresizingMaskIntoConstraints = false
        displayCard.pin(
            displaysStack,
            insets: NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        )

        pauseSwitch.target = switchTarget { [weak self] _ in
            self?.actions.togglePause()
        }
        muteSwitch.target = switchTarget { [weak self] isOn in
            self?.actions.setMuted(isOn)
        }
        desktopIconsSwitch.target = switchTarget { [weak self] isOn in
            self?.actions.setDesktopIconsHidden(isOn)
        }
        desktopIconsSwitch.setAccessibilityLabel("Hide Desktop Icons")

        pauseRow = SettingsRow(
            symbol: "pause.circle",
            title: "Pause Wallpaper",
            subtitle: nil,
            trailing: pauseSwitch
        )
        let muteRow = SettingsRow(
            symbol: "speaker.slash",
            title: "Mute Audio",
            trailing: muteSwitch
        )
        muteRow.toolTip = "Mute audio on every display."
        desktopIconsRow = SettingsRow(
            symbol: "desktopcomputer",
            title: "Hide Desktop Icons",
            trailing: desktopIconsSwitch
        )
        let quickCard = GroupedSection(
            title: nil,
            rows: [
                pauseRow, HairlineView(),
                muteRow, HairlineView(),
                desktopIconsRow,
            ]
        )

        updateNotice.target = self
        updateNotice.action = #selector(downloadUpdate)
        updateNotice.translatesAutoresizingMaskIntoConstraints = false
        updateNotice.heightAnchor.constraint(equalToConstant: 24).isActive = true
        updateNotice.font = Theme.caption
        updateNotice.isHidden = true

        let footerSeparator = HairlineView()
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false

        let preferences = HoverButton(
            "Preferences…",
            symbol: "gearshape",
            style: .borderless,
            target: self,
            action: #selector(openSettings)
        )
        preferences.translatesAutoresizingMaskIntoConstraints = false
        preferences.heightAnchor.constraint(equalToConstant: 24).isActive = true
        preferences.font = Theme.caption

        let support = IconButton(
            symbol: "heart",
            pointSize: 11,
            style: .quiet,
            toolTip: "Support Tangent",
            target: self,
            action: #selector(openSupport)
        )
        let quit = HoverButton(
            "Quit",
            style: .borderless,
            target: self,
            action: #selector(quit)
        )
        quit.translatesAutoresizingMaskIntoConstraints = false
        quit.heightAnchor.constraint(equalToConstant: 24).isActive = true
        quit.font = Theme.caption

        let footer = hstack([preferences, flexibleSpacer(), support, quit], spacing: 4)
        footer.translatesAutoresizingMaskIntoConstraints = false

        let stack = vstack(
            [
                header,
                preview,
                actionRow,
                displaysHeader,
                displayCard,
                quickCard,
                updateNotice,
                footerSeparator,
                footer,
            ],
            spacing: Theme.Spacing.small
        )
        stack.setCustomSpacing(12, after: header)
        stack.setCustomSpacing(10, after: preview)
        stack.setCustomSpacing(18, after: actionRow)
        stack.setCustomSpacing(6, after: displaysHeader)
        stack.setCustomSpacing(16, after: displayCard)
        stack.setCustomSpacing(14, after: quickCard)
        stack.setCustomSpacing(8, after: footerSeparator)

        contentStack = stack
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            displaysHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            displayCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            quickCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            updateNotice.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        reload()
    }

    private func libraryButton() -> NSButton {
        IconButton(
            symbol: "square.grid.2x2",
            pointSize: 11,
            style: .quiet,
            toolTip: "Open Library",
            target: self,
            action: #selector(openLibrary)
        )
    }

    private func manageDisplaysButton() -> NSButton {
        let button = HoverButton(
            "Manage",
            style: .borderless,
            target: self,
            action: #selector(openDisplays)
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        button.font = Theme.tiny
        return button
    }

    private func switchTarget(_ handler: @escaping (Bool) -> Void) -> ActionTarget {
        let target = ActionTarget { sender in
            handler((sender as? NSSwitch)?.state == .on)
        }
        targets.append(target)
        return target
    }

    // MARK: - Presentation

    func show(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Finder can change this setting while Tangent is running; re-read it
        // before measuring the popover so the switch always reflects Finder.
        actions.refreshDesktopIcons()
        reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // NSPopover lowers the content view's width constraint while it sizes
        // the window, which lets a long display name widen the popover. Put the
        // fixed width back and measure the content at that width.
        widthConstraint.priority = .required
        view.layoutSubtreeIfNeeded()
        let size = NSSize(width: 340, height: popoverHeight())
        popover.contentSize = size
        preferredContentSize = size
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    var isShown: Bool { popover.isShown }

    func reload() {
        _ = view
        widthConstraint.priority = .required
        snapshot = actions.snapshot()
        updateHeader()
        updatePreview()
        updateDisplays()
        updateSwitches()
        updateActions()
        updateUpdateNotice()
        view.layoutSubtreeIfNeeded()
        let size = NSSize(width: 340, height: popoverHeight())
        preferredContentSize = size
        popover.contentSize = size
    }

    /// Height that fits the stack plus the popover's own insets.
    private func popoverHeight() -> CGFloat {
        ceil(contentStack.fittingSize.height + 16 + 12)
    }

    // MARK: - Refresh

    private func updateHeader() {
        if snapshot.defaultConfig == nil {
            statePill.configure(text: "No Wallpaper", tint: .secondaryLabelColor)
        } else if snapshot.isPaused {
            statePill.configure(text: "Paused", tint: .systemOrange)
        } else {
            statePill.configure(text: "Live", tint: .systemGreen)
        }
    }

    private func updatePreview() {
        preview.set(pack: snapshot.currentPack, fallback: snapshot.defaultConfig)
    }

    private func updateActions() {
        let hasWallpaper = snapshot.defaultConfig != nil
        playButton.isEnabled = hasWallpaper
        nextButton.isEnabled = snapshot.packCount > 0
        propertiesButton.isEnabled = hasWallpaper
            && [.web, .webaudio, .url].contains(snapshot.defaultConfig?.type ?? .video)

        playButton.title = snapshot.isPaused ? "Resume" : "Pause"
        playButton.image = Symbols.image(
            snapshot.isPaused ? "play.fill" : "pause.fill",
            pointSize: 11,
            weight: .semibold
        )
        playButton.applyStyle()
    }

    private func updateUpdateNotice() {
        guard let update = snapshot.updateState.update else {
            updateNotice.isHidden = true
            return
        }
        updateNotice.title = "Tangent \(update.version) is available"
        updateNotice.toolTip = update.isDirectDownload
            ? "Open the official download for this Mac"
            : "Open the official release page"
        updateNotice.isHidden = false
    }

    private func updateSwitches() {
        pauseSwitch.state = snapshot.pauseReasons.contains(.user) ? .on : .off
        pauseSwitch.isEnabled = snapshot.defaultConfig != nil
        muteSwitch.state = snapshot.isMuted ? .on : .off
        muteSwitch.isEnabled = snapshot.defaultConfig != nil
        pauseRow.toolTip = snapshot.pauseDescription

        desktopIconsSwitch.state = snapshot.desktopIconsState.isHidden ? .on : .off
        desktopIconsSwitch.isEnabled = !snapshot.desktopIconsBusy
        desktopIconsRow.toolTip = desktopIconsHelp
    }

    private var desktopIconsHelp: String {
        if snapshot.desktopIconsBusy {
            return "Updating desktop icons…"
        }
        if let failure = snapshot.desktopIconsState.failure {
            return "Couldn’t update desktop icons. \(failure)"
        }
        if snapshot.desktopIconsState.isHidden {
            return "Desktop icons are hidden. Turn this off to show them again."
        }
        return "Hide every item on the desktop. Finder restarts briefly."
    }

    private func updateDisplays() {
        for view in displaysStack.arrangedSubviews {
            displaysStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !snapshot.displays.isEmpty else {
            let empty = makeLabel(
                "No displays connected",
                font: Theme.caption,
                color: .secondaryLabelColor
            )
            empty.translatesAutoresizingMaskIntoConstraints = false
            displaysStack.addArrangedSubview(empty)
            empty.heightAnchor.constraint(equalToConstant: 26).isActive = true
            empty.widthAnchor.constraint(equalTo: displaysStack.widthAnchor, constant: -12).isActive = true
            return
        }

        for display in snapshot.displays.prefix(4) {
            let row = DisplayPopoverRow(
                display: display,
                defaultTitle: snapshot.defaultConfig?.title
            )
            row.target = self
            row.action = #selector(openDisplays)
            row.translatesAutoresizingMaskIntoConstraints = false
            displaysStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: displaysStack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }

    // MARK: - Actions

    @objc private func togglePause() { actions.togglePause() }
    @objc private func nextWallpaper() { actions.nextWallpaper() }
    @objc private func openProperties() { actions.openProperties(nil) }
    @objc private func openLibrary() { close(); actions.openLibrary() }
    @objc private func openDisplays() { close(); actions.openLibrarySection(.displays) }
    @objc private func openSettings() { close(); actions.openSettings() }
    @objc private func downloadUpdate() { close(); actions.downloadUpdate() }
    @objc private func openSupport() {
        close()
        KoFiSupportWindowController.shared.present()
    }
    @objc private func quit() { actions.quit() }
}

// MARK: - Preview

/// The hero preview: a thumbnail with the wallpaper title composited over a
/// bottom scrim, the way system media surfaces present artwork.
private final class PopoverPreviewView: NSView {

    private let imageView = NSImageView()
    private let scrim = CAGradientLayer()
    private let titleLabel = makeLabel("No wallpaper", font: Theme.font(15, .semibold), color: .white)
    private let subtitleLabel = makeLabel("", font: Theme.tiny, color: NSColor.white.withAlphaComponent(0.78))
    private let overlay = BadgeView()
    private var currentID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Theme.Radius.card
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.previewPlaceholder.cgColor

        imageView.imageScaling = .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // An image view reports the image's pixel size as its intrinsic size.
        // Left at the default compression resistance, a 512 pt thumbnail makes
        // NSPopover widen itself to match. The preview is 340 pt wide by design,
        // so the image gives up its intrinsic width first.
        imageView.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        imageView.setContentCompressionResistancePriority(.init(1), for: .vertical)
        addSubview(imageView)

        scrim.colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.55).cgColor,
            NSColor.black.withAlphaComponent(0.82).cgColor,
        ]
        scrim.locations = [0, 0.55, 1]
        layer?.addSublayer(scrim)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(overlay)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlay.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -2),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),

            heightAnchor.constraint(equalToConstant: 168),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.previewPlaceholder.cgColor
    }

    func set(pack: Pack?, fallback: WallpaperConfig? = nil) {
        guard let pack else {
            currentID = nil
            imageView.image = nil
            titleLabel.stringValue = fallback?.title ?? "No wallpaper"
            subtitleLabel.stringValue = fallback?.type.displayName
                ?? "Choose one from the library"
            overlay.isHidden = fallback == nil
            if let fallback {
                overlay.configure(
                    text: fallback.type.displayName.uppercased(),
                    symbol: fallback.type.glyph,
                    tint: .white,
                    background: NSColor.black.withAlphaComponent(0.5)
                )
            }
            return
        }

        currentID = pack.id
        titleLabel.stringValue = pack.info.title
        subtitleLabel.stringValue = pack.info.author.map { "by \($0)" } ?? pack.info.type.displayName
        overlay.isHidden = false
        overlay.configure(
            text: pack.info.type.displayName.uppercased(),
            symbol: pack.info.type.glyph,
            tint: .white,
            background: NSColor.black.withAlphaComponent(0.5)
        )

        let identifier = pack.id
        Task { [weak self] in
            let image = await ThumbnailProvider.shared.thumbnail(for: pack)
            await MainActor.run {
                guard let self, self.currentID == identifier else { return }
                self.imageView.image = image
            }
        }
    }
}

// MARK: - Display row

/// One connected display inside the popover.
private final class DisplayPopoverRow: NSButton {

    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let badge = BadgeView()

    init(display: DisplaySummary, defaultTitle: String?) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        icon.image = Symbols.image(
            display.isMain ? "laptopcomputer" : "display",
            pointSize: 11,
            weight: .medium
        )
        icon.contentTintColor = display.isDisabled ? .tertiaryLabelColor : Theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false

        // The laptop icon already says which display is the main one, so the
        // row drops the "(Main)" suffix and keeps the full name readable.
        name.stringValue = display.label.replacingOccurrences(of: " (Main)", with: "")
        name.font = Theme.caption
        name.textColor = display.isDisabled ? .secondaryLabelColor : .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        // Long display and wallpaper names must truncate, not widen the
        // popover: it is a fixed 340 pt surface.
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stateLabel.stringValue = display.state
        stateLabel.font = Theme.tiny
        stateLabel.textColor = .tertiaryLabelColor
        stateLabel.alignment = .right
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let trailing: NSView
        if display.isDisabled {
            badge.configure(text: "Off", tint: .systemOrange)
            trailing = badge
        } else if display.isPinned {
            badge.configure(text: "Pinned", tint: .systemBlue)
            trailing = badge
        } else if display.config?.title == defaultTitle {
            // Same wallpaper as the hero preview above: no need to repeat it.
            stateLabel.stringValue = ""
            trailing = stateLabel
        } else {
            trailing = stateLabel
        }
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(name)
        addSubview(trailing)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),

            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -6),
            stateLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 130),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

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
        isHovered = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    private func updateStyle() {
        layer?.backgroundColor = isHovered ? Theme.rowHover.cgColor : NSColor.clear.cgColor
    }
}
