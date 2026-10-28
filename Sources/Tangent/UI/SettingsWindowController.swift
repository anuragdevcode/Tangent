import AppKit
import Carbon.HIToolbox

/// Settings window. Four panes, all AppKit so the CLT-only build works:
/// General (library), Playback (rules), Shortcuts (global hot keys), About.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let actions: AppActions
    private let hotkeys: HotkeyManager
    private let onHotkeysChange: () -> Void

    private var targets: [ActionTarget] = []
    private var paneContainer: NSView!
    private var paneSelector: NSSegmentedControl!
    private var panes: [NSView] = []

    private var packCountLabel: NSTextField!
    private var hiddenCountLabel: NSTextField!
    private var restoreButton: HoverButton!
    private var libraryPathLabel: NSTextField!

    private var fullscreenSwitch: NSSwitch!
    private var batterySwitch: NSSwitch!
    private var lockSwitch: NSSwitch!
    private var statusPill: StatusPillView!
    private var statusTitle: NSTextField!
    private var statusDetail: NSTextField!

    private var hotkeySwitch: NSSwitch!
    private var hotkeyStatusLabel: NSTextField!
    private var hotkeyButtons: [HotkeyManager.Action: HoverButton] = [:]
    private var bindingMessageLabel: NSTextField!
    private var recordingAction: HotkeyManager.Action?
    private var keyMonitor: Any?

    init(
        actions: AppActions,
        hotkeys: HotkeyManager,
        onHotkeysChange: @escaping () -> Void
    ) {
        self.actions = actions
        self.hotkeys = hotkeys
        self.onHotkeysChange = onHotkeysChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.center()

        super.init(window: window)
        window.delegate = self
        buildInterface()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - Presentation

    func present() {
        finishRecording()
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        finishRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        cancelRecording()
    }

    /// Called when the menu's hotkey toggle changes while this window is open.
    func reload() { refresh() }

    /// Selects a pane for scripted snapshots (`--settings-pane N`).
    func selectPane(_ index: Int) {
        guard panes.indices.contains(index) else { return }
        paneSelector.selectedSegment = index
        paneChanged()
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        let background = VisualEffectView(material: .contentBackground, blending: .behindWindow)
        background.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        paneSelector = NSSegmentedControl(
            labels: ["General", "Playback", "Shortcuts", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(paneChanged)
        )
        paneSelector.selectedSegment = 0
        paneSelector.controlSize = .regular
        paneSelector.segmentStyle = .automatic
        paneSelector.translatesAutoresizingMaskIntoConstraints = false

        paneContainer = NSView()
        paneContainer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(paneSelector)
        content.addSubview(paneContainer)

        NSLayoutConstraint.activate([
            paneSelector.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            paneSelector.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            paneSelector.widthAnchor.constraint(equalToConstant: 390),

            paneContainer.topAnchor.constraint(equalTo: paneSelector.bottomAnchor, constant: 2),
            paneContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        panes = [generalPane(), playbackPane(), shortcutsPane(), aboutPane()]
        for (index, pane) in panes.enumerated() {
            pane.translatesAutoresizingMaskIntoConstraints = false
            paneContainer.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
            ])
            pane.isHidden = index != 0
        }
    }

    @objc private func paneChanged() {
        cancelRecording()
        for (index, pane) in panes.enumerated() {
            pane.isHidden = index != paneSelector.selectedSegment
        }
    }

    // MARK: - General

    private func generalPane() -> NSView {
        let mark = BrandMarkView(size: 54)
        let title = makeLabel("Tangent", font: Theme.font(26, .bold))
        let subtitle = makeLabel(
            "Native wallpaper engine for macOS",
            font: Theme.callout,
            color: .secondaryLabelColor
        )
        let version = BadgeView(text: Format.version(), symbol: "checkmark.seal", tint: Theme.accent)
        let titleBlock = vstack([title, subtitle, version], spacing: 3, alignment: .leading)
        let header = hstack([mark, titleBlock], spacing: 14)

        packCountLabel = makeLabel("", font: Theme.caption, color: .secondaryLabelColor)
        hiddenCountLabel = makeLabel("", font: Theme.caption, color: .secondaryLabelColor)
        libraryPathLabel = makeLabel("", font: Theme.caption, color: .secondaryLabelColor)
        libraryPathLabel.lineBreakMode = .byTruncatingMiddle
        libraryPathLabel.toolTip = PackLibrary.defaultRoot.path

        restoreButton = smallButton("Restore", action: actions.restoreHidden)
        restoreButton.toolTip = "Bring wallpapers removed from the library back"

        let librarySection = GroupedSection(
            title: "Wallpaper Library",
            rows: [
                SettingsRow(
                    symbol: "square.grid.2x2",
                    title: "Wallpapers",
                    subtitle: "Referenced in place — adding a folder never copies it.",
                    trailing: trailingLabel(packCountLabel)
                ),
                HairlineView(),
                SettingsRow(
                    symbol: "folder",
                    title: "Library Folder",
                    subtitle: nil,
                    trailing: smallButton("Show in Finder", action: actions.revealLibraryFolder)
                ),
                HairlineView(),
                SettingsRow(
                    symbol: "eye.slash",
                    title: "Hidden Wallpapers",
                    subtitle: "Removed through the app stay on disk. Restore them here.",
                    trailing: hstack(
                        [
                            hiddenCountLabel,
                            restoreButton,
                        ],
                        spacing: 10
                    )
                ),
            ]
        )

        let folderRow = SettingsRow(
            symbol: "externaldrive",
            title: "Location",
            subtitle: nil,
            trailing: trailingLabel(libraryPathLabel)
        )

        let actionsSection = GroupedSection(
            title: "Manage",
            rows: [
                SettingsRow(
                    symbol: "plus",
                    title: "Add Wallpaper…",
                    subtitle: "Video, image, GIF, web page or a wallpaper pack folder.",
                    trailing: smallButton("Add", action: actions.addWallpaper)
                ),
                HairlineView(),
                SettingsRow(
                    symbol: "square.grid.2x2.fill",
                    title: "Open Library",
                    subtitle: "Browse, search and apply wallpapers.",
                    trailing: smallButton("Open", action: actions.openLibrary)
                ),
            ]
        )

        let note = makeWrappingLabel(
            "Tangent lives in the menu bar. Use the sparkles icon to change, pause or stop "
            + "the wallpaper without opening this window.",
            font: Theme.caption,
            color: .tertiaryLabelColor
        )
        note.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

        let stack = vstack(
            [header, spacing(6), librarySection, folderRow, actionsSection, note],
            spacing: Theme.Spacing.regular
        )
        stack.setCustomSpacing(20, after: header)
        for wide in [librarySection, folderRow, actionsSection] {
            wide.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return wrapInPage(stack)
    }

    private func trailingLabel(_ label: NSTextField) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> HoverButton {
        let button = HoverButton(title, style: .outlined, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.font = Theme.caption
        let target = ActionTarget { _ in action() }
        targets.append(target)
        button.target = target
        button.action = #selector(ActionTarget.fire(_:))
        return button
    }

    // MARK: - Playback

    private func playbackPane() -> NSView {
        fullscreenSwitch = makeSwitch { [weak self] isOn in
            self?.setPolicy(pauseOnFullscreen: isOn)
        }
        batterySwitch = makeSwitch { [weak self] isOn in
            self?.setPolicy(pauseOnBattery: isOn)
        }
        lockSwitch = makeSwitch { [weak self] isOn in
            self?.setPolicy(pauseOnLock: isOn)
        }

        let statusCard = CardView()
        statusCard.fillColor = Theme.cardFill
        statusCard.translatesAutoresizingMaskIntoConstraints = false

        statusPill = StatusPillView(text: "Live", tint: .systemGreen)
        statusTitle = makeLabel("Rendering live", font: Theme.cardTitle)
        statusDetail = makeWrappingLabel("", font: Theme.caption, color: .secondaryLabelColor)
        let statusText = vstack([statusTitle, statusDetail], spacing: 2)
        let statusRow = hstack([statusPill, statusText], spacing: 10)
        statusCard.pin(statusRow, insets: NSEdgeInsets(top: 13, left: 13, bottom: 13, right: 13))

        let rules = GroupedSection(
            title: "Playback Rules",
            rows: [
                SettingsRow(
                    symbol: "rectangle.inset.filled",
                    title: "Pause for Fullscreen Apps",
                    subtitle: "Stop rendering while an app covers the main display.",
                    trailing: fullscreenSwitch
                ),
                HairlineView(),
                SettingsRow(
                    symbol: "battery.50percent",
                    title: "Pause on Battery",
                    subtitle: "Save power when the Mac is unplugged.",
                    trailing: batterySwitch
                ),
                HairlineView(),
                SettingsRow(
                    symbol: "lock.display",
                    title: "Pause When the Screen Locks",
                    subtitle: "Stop decoding while the display is asleep or locked.",
                    trailing: lockSwitch
                ),
            ]
        )

        let note = makeWrappingLabel(
            "Rules are independent: playback resumes only when every reason has cleared, so "
            + "closing a fullscreen app will not undo a manual pause.",
            font: Theme.caption,
            color: .tertiaryLabelColor
        )
        note.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

        let stack = vstack(
            [makeLabel("Playback", font: Theme.windowTitle), statusCard, rules, note],
            spacing: Theme.Spacing.regular
        )
        for wide in [statusCard, rules] {
            wide.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return wrapInPage(stack)
    }

    private func setPolicy(
        pauseOnFullscreen: Bool? = nil,
        pauseOnBattery: Bool? = nil,
        pauseOnLock: Bool? = nil
    ) {
        var policy = actions.snapshot().policy
        if let pauseOnFullscreen { policy.pauseOnFullscreen = pauseOnFullscreen }
        if let pauseOnBattery { policy.pauseOnBattery = pauseOnBattery }
        if let pauseOnLock { policy.pauseOnLock = pauseOnLock }
        actions.setPolicy(policy)
        refresh()
    }

    // MARK: - Shortcuts

    private func shortcutsPane() -> NSView {
        hotkeySwitch = makeSwitch { [weak self] isOn in
            self?.actions.setHotkeysEnabled(isOn)
            self?.refresh()
            self?.onHotkeysChange()
        }

        hotkeyStatusLabel = makeWrappingLabel("", font: Theme.caption, color: .secondaryLabelColor)
        hotkeyStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

        var rows: [NSView] = []
        for action in HotkeyManager.Action.allCases {
            let button = HoverButton(
                hotkeys.binding(for: action).display,
                style: .outlined,
                target: nil,
                action: nil
            )
            button.tag = Int(action.identifier)
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            button.toolTip = "Click, then press a new combination"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 118).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            button.target = self
            button.action = #selector(beginRecording(_:))
            hotkeyButtons[action] = button

            if !rows.isEmpty { rows.append(HairlineView()) }
            rows.append(
                SettingsRow(
                    symbol: actionGlyph(action),
                    title: action.title,
                    trailing: button
                )
            )
        }

        let shortcuts = GroupedSection(title: "Global Shortcuts", rows: rows)

        let toggleSection = GroupedSection(
            title: nil,
            rows: [
                SettingsRow(
                    symbol: "command",
                    title: "Enable Global Shortcuts",
                    subtitle: "Work while another app is frontmost. Carbon hot keys need no extra permission.",
                    trailing: hotkeySwitch
                )
            ]
        )

        bindingMessageLabel = makeWrappingLabel("", font: Theme.caption, color: .secondaryLabelColor)
        bindingMessageLabel.isHidden = true

        let resetAll = smallButton("Reset All Shortcuts", action: resetAllShortcuts)
        let footerRow = hstack([resetAll, flexibleSpacer()])

        let note = makeWrappingLabel(
            "Click a shortcut, then press a new combination. Escape cancels; Delete restores the default.",
            font: Theme.caption,
            color: .tertiaryLabelColor
        )
        note.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

        let stack = vstack(
            [
                makeLabel("Shortcuts", font: Theme.windowTitle),
                toggleSection,
                shortcuts,
                bindingMessageLabel,
                footerRow,
                hotkeyStatusLabel,
                note,
            ],
            spacing: Theme.Spacing.regular
        )
        for wide in [toggleSection, shortcuts, footerRow] {
            wide.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return wrapInPage(stack)
    }

    private func actionGlyph(_ action: HotkeyManager.Action) -> String {
        switch action {
        case .togglePause: return "pause.circle"
        case .nextWallpaper: return "forward.end"
        case .openLibrary: return "square.grid.2x2"
        case .stopWallpaper: return "stop.circle"
        }
    }

    // MARK: - About

    private func aboutPane() -> NSView {
        wrapInPage(AboutContent.page(centered: true), maxWidth: 460)
    }

    // MARK: - Page scaffold

    private func wrapInPage(_ content: NSView, maxWidth: CGFloat = 540) -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let scroll = makePageScroll(content: content, maxWidth: maxWidth)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    // MARK: - Switches

    private func makeSwitch(_ handler: @escaping (Bool) -> Void) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        let target = ActionTarget { sender in
            handler((sender as? NSSwitch)?.state == .on)
        }
        targets.append(target)
        toggle.target = target
        toggle.action = #selector(ActionTarget.fire(_:))
        return toggle
    }

    // MARK: - Refresh

    private func refresh() {
        let snapshot = actions.snapshot()
        let policy = snapshot.policy
        fullscreenSwitch?.state = policy.pauseOnFullscreen ? .on : .off
        batterySwitch?.state = policy.pauseOnBattery ? .on : .off
        lockSwitch?.state = policy.pauseOnLock ? .on : .off

        hotkeySwitch?.state = snapshot.hotkeysEnabled ? .on : .off
        refreshBindingButtons()
        refreshHotkeyStatus()

        packCountLabel?.stringValue = Format.count(snapshot.packCount, singular: "wallpaper")
        libraryPathLabel?.stringValue = Format.relativePath(PackLibrary.defaultRoot)
        hiddenCountLabel?.stringValue = snapshot.hiddenCount == 0
            ? ""
            : Format.count(snapshot.hiddenCount, singular: "hidden")
        restoreButton?.isEnabled = snapshot.hiddenCount > 0

        if let statusPill, let statusTitle, let statusDetail {
            if snapshot.defaultConfig == nil {
                statusPill.configure(text: "Off", tint: .secondaryLabelColor)
                statusTitle.stringValue = "No wallpaper set"
                statusDetail.stringValue = "Choose one from the library to bring the desktop to life."
            } else {
                statusPill.configure(
                    text: snapshot.isPaused ? "Paused" : "Live",
                    tint: snapshot.isPaused ? .systemOrange : .systemGreen
                )
                statusTitle.stringValue = snapshot.isPaused ? "Rendering paused" : "Rendering live"
                statusDetail.stringValue = snapshot.pauseDescription
                    ?? "\(snapshot.statusDescription)."
            }
        }
    }

    private func refreshHotkeyStatus() {
        hotkeyStatusLabel?.stringValue = hotkeys.statusDescription
        hotkeyStatusLabel?.textColor = hotkeys.failures.isEmpty && hotkeys.isEnabled
            ? .secondaryLabelColor
            : (hotkeys.isEnabled ? .systemOrange : .secondaryLabelColor)
    }

    private func refreshBindingButtons() {
        guard recordingAction == nil else { return }
        for action in HotkeyManager.Action.allCases {
            guard let button = hotkeyButtons[action] else { continue }
            button.title = hotkeys.binding(for: action).display
            button.applyStyle()
            button.toolTip = hotkeys.isCustomized(action)
                ? "Custom shortcut — click to change"
                : "Default shortcut — click to change"
        }
    }

    // MARK: - Shortcut recorder

    @objc private func beginRecording(_ sender: HoverButton) {
        guard let action = HotkeyManager.Action.action(for: UInt32(sender.tag)) else { return }
        finishRecording()

        recordingAction = action
        for button in hotkeyButtons.values { button.isEnabled = false }
        sender.isEnabled = true
        sender.title = "Press keys…"
        sender.applyStyle()

        showBindingMessage(
            "Press the new keys for \(action.title). Escape cancels; Delete restores the default.",
            color: .secondaryLabelColor
        )

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }
            return self.capture(event, for: action)
        }
    }

    /// Swallows the captured key so it cannot trigger a menu item or beep.
    private func capture(_ event: NSEvent, for action: HotkeyManager.Action) -> NSEvent? {
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            showBindingMessage("Shortcut unchanged.", color: .secondaryLabelColor)
            return nil
        }

        let flags = event.modifierFlags
        let hasControlOptionOrCommand = flags.contains(.control)
            || flags.contains(.option)
            || flags.contains(.command)
        let isDelete = event.keyCode == UInt16(kVK_Delete)
            || event.keyCode == UInt16(kVK_ForwardDelete)
        if isDelete, !hasControlOptionOrCommand {
            hotkeys.resetBinding(for: action)
            finishRecording()
            refreshHotkeyStatus()
            onHotkeysChange()
            showBindingMessage(
                "\(action.title) restored to \(hotkeys.binding(for: action).display).",
                color: .secondaryLabelColor
            )
            return nil
        }

        guard let binding = HotkeyManager.KeyBinding(event: event) else {
            showBindingMessage("Hold Control or Option with another key.", color: .systemOrange)
            return nil
        }

        do {
            try hotkeys.setBinding(binding, for: action)
        } catch let error as HotkeyManager.BindingError {
            showBindingMessage(error.message, color: .systemOrange)
            return nil
        } catch {
            showBindingMessage("Could not set that shortcut.", color: .systemOrange)
            return nil
        }

        finishRecording()
        refreshHotkeyStatus()
        onHotkeysChange()
        let display = hotkeys.binding(for: action).display
        if hotkeys.failures[action] != nil {
            showBindingMessage(
                "\(action.title) saved as \(display), but another app already uses it.",
                color: .systemOrange
            )
        } else {
            showBindingMessage(
                "\(action.title) is now \(display).",
                color: .secondaryLabelColor
            )
        }
        return nil
    }

    private func cancelRecording() {
        guard recordingAction != nil else { return }
        finishRecording()
        showBindingMessage("Recording cancelled.", color: .secondaryLabelColor)
    }

    private func finishRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingAction = nil
        for button in hotkeyButtons.values { button.isEnabled = true }
        refreshBindingButtons()
    }

    private func showBindingMessage(_ text: String, color: NSColor) {
        bindingMessageLabel?.stringValue = text
        bindingMessageLabel?.textColor = color
        bindingMessageLabel?.isHidden = text.isEmpty
    }

    private func resetAllShortcuts() {
        finishRecording()
        hotkeys.resetAllBindings()
        refreshHotkeyStatus()
        onHotkeysChange()
        showBindingMessage("All shortcuts restored to defaults.", color: .secondaryLabelColor)
    }
}
