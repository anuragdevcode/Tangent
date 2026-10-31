import AppKit

// MARK: - Page scaffold

/// A vertically scrolling page with a centered column, used by Displays,
/// Automation and About.
func makePageScroll(content: NSView, maxWidth: CGFloat = 660) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let document = FlippedDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = document
    document.addSubview(content)

    // The page column *may* fill the scroll view, but it never insists on it.
    // At `.defaultHigh` the solver could satisfy this preference by resizing the
    // window itself (visible when the inspector collapses and the content area
    // grows), which made the window jump on every section switch. Keeping it
    // low leaves the window size in charge and centers the column instead.
    let width = content.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -56)
    width.priority = .defaultLow
    NSLayoutConstraint.activate([
        document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        content.topAnchor.constraint(equalTo: document.topAnchor, constant: 26),
        content.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 28),
        content.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
        content.centerXAnchor.constraint(equalTo: document.centerXAnchor),
        width,
        content.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
        content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
    ])
    return scrollView
}

// MARK: - Displays

/// Per-display wallpaper mapping, built from the live layout.
final class DisplaysPageView: NSView {

    private let actions: AppActions
    private let snapshot: AppSnapshot
    private var targets: [ActionTarget] = []

    init(actions: AppActions, snapshot: AppSnapshot) {
        self.actions = actions
        self.snapshot = snapshot
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private func build() {
        let title = makeLabel("Displays", font: Theme.windowTitle)
        let subtitle = makeWrappingLabel(
            "Each connected display runs its own wallpaper window. Pin a display to keep it on a "
            + "different wallpaper when the default changes, or turn it off entirely.",
            font: Theme.callout,
            color: .secondaryLabelColor
        )
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true

        var cards: [NSView] = []
        for display in snapshot.displays {
            cards.append(card(for: display))
        }

        var views: [NSView] = [title, subtitle, spacing(6)]
        for card in cards {
            views.append(card)
        }

        if snapshot.displays.contains(where: { $0.isPinned || $0.isDisabled }) {
            let reset = HoverButton(
                "Reset Per-Display Layout",
                symbol: "arrow.uturn.backward",
                style: .outlined,
                target: nil,
                action: nil
            )
            reset.translatesAutoresizingMaskIntoConstraints = false
            reset.heightAnchor.constraint(equalToConstant: 28).isActive = true
            let target = ActionTarget { [weak self] _ in
                self?.actions.resetDisplayOverrides()
            }
            targets.append(target)
            reset.target = target
            reset.action = #selector(ActionTarget.fire(_:))
            views.append(hstack([reset]))
        }

        let note = makeWrappingLabel(
            "A wallpaper cannot stretch across displays; use the same wallpaper on each one for a "
            + "cloned look. Assignments are keyed by display, so they survive restarts and reconnects.",
            font: Theme.caption,
            color: .tertiaryLabelColor
        )
        note.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true
        views.append(note)

        let stack = vstack(views, spacing: Theme.Spacing.medium)
        stack.setCustomSpacing(18, after: subtitle)
        for card in cards {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let scroll = makePageScroll(content: stack)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func card(for display: DisplaySummary) -> NSView {
        let card = CardView()
        card.fillColor = Theme.cardFill
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true

        let iconCard = CardView()
        iconCard.radius = 9
        iconCard.fillColor = display.isDisabled
            ? Theme.controlFill
            : Theme.accent.withAlphaComponent(0.14)
        iconCard.translatesAutoresizingMaskIntoConstraints = false
        let icon = Symbols.view(
            display.isMain ? "laptopcomputer" : "display",
            pointSize: 16,
            weight: .regular,
            color: display.isDisabled ? .tertiaryLabelColor : Theme.accent
        )
        iconCard.addSubview(icon)
        NSLayoutConstraint.activate([
            iconCard.widthAnchor.constraint(equalToConstant: 36),
            iconCard.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: iconCard.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconCard.centerYAnchor),
        ])

        let name = makeLabel(display.label, font: Theme.cardTitle)
        let state = makeLabel(display.state, font: Theme.caption, color: .secondaryLabelColor)
        let text = vstack([name, state], spacing: 2)

        var badges: [NSView] = []
        if display.isMain {
            badges.append(BadgeView(text: "Main", tint: .secondaryLabelColor))
        }
        if display.isDisabled {
            badges.append(BadgeView(text: "Off", tint: .systemOrange))
        } else if display.isPinned {
            badges.append(BadgeView(text: "Pinned", symbol: "pin.fill", tint: .systemBlue))
        }
        let badgeRow = hstack(badges, spacing: 5)

        let useDefault = actionButton(
            "Use Default",
            symbol: "arrow.turn.down.right",
            active: snapshot.defaultConfig != nil && !display.isPinned && !display.isDisabled
        ) { [weak self] in
            self?.actions.useDefaultForDisplay(display.id)
        }
        useDefault.isEnabled = snapshot.defaultConfig != nil

        let pin = actionButton(
            "Pin Current",
            symbol: "pin",
            active: display.isPinned && !display.isDisabled
        ) { [weak self] in
            self?.actions.pinCurrentToDisplay(display.id)
        }
        pin.isEnabled = snapshot.defaultConfig != nil

        let off = actionButton("Turn Off", symbol: "power", active: display.isDisabled) { [weak self] in
            self?.actions.turnOffDisplay(display.id)
        }
        off.contentTintColor = display.isDisabled ? .systemOrange : .secondaryLabelColor

        let controls = hstack([useDefault, pin, off], spacing: 6)
        let topRow = hstack([iconCard, text, flexibleSpacer(), badgeRow], spacing: 11)
        let content = vstack([topRow, controls], spacing: 12)

        card.pin(content, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> HoverButton {
        let button = HoverButton(
            title,
            symbol: symbol,
            style: active ? .accent : .outlined,
            target: nil,
            action: nil
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let target = ActionTarget { _ in action() }
        targets.append(target)
        button.target = target
        button.action = #selector(ActionTarget.fire(_:))
        return button
    }
}

// MARK: - Automation

/// Playback rules and shortcut status.
final class AutomationPageView: NSView {

    private let actions: AppActions
    private let snapshot: AppSnapshot
    private var targets: [ActionTarget] = []

    init(actions: AppActions, snapshot: AppSnapshot) {
        self.actions = actions
        self.snapshot = snapshot
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private func build() {
        let title = makeLabel("Automation", font: Theme.windowTitle)
        let subtitle = makeWrappingLabel(
            "Tangent can step out of the way automatically. These rules apply to every display and "
            + "pause only the wallpaper — never your applications.",
            font: Theme.callout,
            color: .secondaryLabelColor
        )
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true

        let policy = snapshot.policy
        let rows = [
            SettingsRow(
                symbol: "rectangle.inset.filled",
                title: "Pause for Fullscreen Apps",
                subtitle: "Stop rendering while an app covers the main display.",
                trailing: toggle(isOn: policy.pauseOnFullscreen) { [weak self] isOn in
                    guard var policy = self?.actions.snapshot().policy else { return }
                    policy.pauseOnFullscreen = isOn
                    self?.actions.setPolicy(policy)
                }
            ),
            SettingsRow(
                symbol: "battery.50percent",
                title: "Pause on Battery",
                subtitle: "Save power when the Mac is unplugged.",
                trailing: toggle(isOn: policy.pauseOnBattery) { [weak self] isOn in
                    guard var policy = self?.actions.snapshot().policy else { return }
                    policy.pauseOnBattery = isOn
                    self?.actions.setPolicy(policy)
                }
            ),
            SettingsRow(
                symbol: "lock.display",
                title: "Pause When the Screen Locks",
                subtitle: "Stop decoding while the display is asleep or locked.",
                trailing: toggle(isOn: policy.pauseOnLock) { [weak self] isOn in
                    guard var policy = self?.actions.snapshot().policy else { return }
                    policy.pauseOnLock = isOn
                    self?.actions.setPolicy(policy)
                }
            ),
        ]

        let rules = GroupedSection(title: "Playback Rules", rows: rows)

        let hotkeyRow = SettingsRow(
            symbol: "command",
            title: "Global Shortcuts",
            subtitle: snapshot.hotkeysEnabled
                ? "\(snapshot.hotkeyStatus)"
                : "Off — enable them to control Tangent from any app.",
            trailing: toggle(isOn: snapshot.hotkeysEnabled) { [weak self] isOn in
                self?.actions.setHotkeysEnabled(isOn)
            }
        )
        let hotkeys = GroupedSection(title: "Shortcuts", rows: [hotkeyRow])

        let statusCard = CardView()
        statusCard.fillColor = Theme.cardFill
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        let hasWallpaper = snapshot.defaultConfig != nil
        let statusColor: NSColor = hasWallpaper
            ? (snapshot.isPaused ? .systemOrange : Theme.accent)
            : .tertiaryLabelColor
        let statusIcon = Symbols.view(
            hasWallpaper ? (snapshot.isPaused ? "pause.circle.fill" : "bolt.fill") : "moon.zzz.fill",
            pointSize: 20,
            weight: .regular,
            color: statusColor
        )
        let statusTitle = makeLabel(
            hasWallpaper
                ? (snapshot.isPaused ? "Rendering paused" : "Rendering live")
                : "No wallpaper set",
            font: Theme.cardTitle
        )
        let statusDetail = makeWrappingLabel(
            hasWallpaper
                ? (snapshot.pauseDescription ?? "Wallpapers are playing normally.")
                : "Choose one from the library to bring the desktop to life.",
            font: Theme.caption,
            color: .secondaryLabelColor
        )
        let statusText = vstack([statusTitle, statusDetail], spacing: 2)
        let statusPill = StatusPillView(
            text: hasWallpaper ? (snapshot.isPaused ? "Paused" : "Live") : "Off",
            tint: hasWallpaper
                ? (snapshot.isPaused ? .systemOrange : .systemGreen)
                : .secondaryLabelColor
        )
        let statusRow = hstack([statusIcon, statusText, inflexibleSpacer(), statusPill], spacing: 12)
        statusCard.pin(statusRow, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        let footer = makeWrappingLabel(
            "Rules are independent: closing a fullscreen app will not undo a manual pause. Changes "
            + "apply immediately and are remembered between launches.",
            font: Theme.caption,
            color: .tertiaryLabelColor
        )
        footer.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true

        let stack = vstack(
            [title, subtitle, spacing(6), statusCard, rules, hotkeys, footer],
            spacing: Theme.Spacing.medium
        )
        stack.setCustomSpacing(18, after: subtitle)
        for wide in [statusCard, rules, hotkeys] {
            wide.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let scroll = makePageScroll(content: stack)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func toggle(isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        let target = ActionTarget { sender in
            onChange((sender as? NSSwitch)?.state == .on)
        }
        targets.append(target)
        toggle.target = target
        toggle.action = #selector(ActionTarget.fire(_:))
        return toggle
    }
}

// MARK: - About

final class AboutPageView: NSView {

    private let content: AboutFeedbackPage

    init(actions: AppActions) {
        content = AboutFeedbackPage(centered: false, actions: actions)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let scroll = makePageScroll(content: content, maxWidth: 640)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    /// Refreshes update status without resetting the page's scroll position.
    func apply(snapshot: AppSnapshot) {
        content.apply(snapshot: snapshot)
    }
}
