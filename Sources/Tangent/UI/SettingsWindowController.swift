import AppKit
import Carbon.HIToolbox

/// Settings window. Four panes, all AppKit so the CLT-only build works:
/// General (library), Playback (rules), Shortcuts (global hot keys), About.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let playback: PlaybackMonitor
    private let hotkeys: HotkeyManager
    private let library: LibraryModel

    private let onPolicyChange: () -> Void
    private let onHotkeysChange: () -> Void
    private let onAddWallpaper: () -> Void
    private let onOpenLibrary: () -> Void
    private let onRevealLibrary: () -> Void

    private var paneContainer: NSView!
    private var paneSelector: NSSegmentedControl!
    private var panes: [NSView] = []
    private var fullscreenButton: NSButton!
    private var batteryButton: NSButton!
    private var lockButton: NSButton!
    private var hotkeyToggle: NSButton!
    private var hotkeyStatusLabel: NSTextField!
    private var hotkeyButtons: [HotkeyManager.Action: NSButton] = [:]
    private var bindingMessageLabel: NSTextField!
    private var recordingAction: HotkeyManager.Action?
    private var keyMonitor: Any?
    private var packCountLabel: NSTextField!
    private var libraryPathLabel: NSTextField!

    init(
        playback: PlaybackMonitor,
        hotkeys: HotkeyManager,
        library: LibraryModel,
        onPolicyChange: @escaping () -> Void,
        onHotkeysChange: @escaping () -> Void,
        onAddWallpaper: @escaping () -> Void,
        onOpenLibrary: @escaping () -> Void,
        onRevealLibrary: @escaping () -> Void
    ) {
        self.playback = playback
        self.hotkeys = hotkeys
        self.library = library
        self.onPolicyChange = onPolicyChange
        self.onHotkeysChange = onHotkeysChange
        self.onAddWallpaper = onAddWallpaper
        self.onOpenLibrary = onOpenLibrary
        self.onRevealLibrary = onRevealLibrary

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tangent Settings"
        window.isReleasedWhenClosed = false
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

        // A segmented header is used instead of NSTabView: it renders
        // consistently in dark mode and in the in-process snapshot path.
        paneSelector = NSSegmentedControl(
            labels: ["General", "Playback", "Shortcuts", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(paneChanged)
        )
        paneSelector.selectedSegment = 0
        paneSelector.translatesAutoresizingMaskIntoConstraints = false

        paneContainer = NSView()
        paneContainer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(paneSelector)
        content.addSubview(paneContainer)

        NSLayoutConstraint.activate([
            paneSelector.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            paneSelector.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            paneContainer.topAnchor.constraint(equalTo: paneSelector.bottomAnchor, constant: 8),
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

    private func makePane() -> (root: NSView, stack: NSStackView) {
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
        ])
        return (root, stack)
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    // MARK: - General

    private func generalPane() -> NSView {
        let (root, stack) = makePane()

        let title = NSTextField(labelWithString: "Tangent")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let subtitle = NSTextField(labelWithString: "Native wallpaper engine for macOS")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        packCountLabel = NSTextField(labelWithString: "")
        packCountLabel.font = .systemFont(ofSize: 12, weight: .medium)

        libraryPathLabel = NSTextField(labelWithString: PackLibrary.defaultRoot.path)
        libraryPathLabel.font = .systemFont(ofSize: 10)
        libraryPathLabel.textColor = .tertiaryLabelColor
        libraryPathLabel.lineBreakMode = .byTruncatingMiddle
        libraryPathLabel.isSelectable = true
        libraryPathLabel.maximumNumberOfLines = 1

        let openButton = NSButton(title: "Open Library…", target: self, action: #selector(openLibraryTapped))
        let addButton = NSButton(title: "Add Wallpaper…", target: self, action: #selector(addWallpaperTapped))
        let revealButton = NSButton(title: "Show Folder", target: self, action: #selector(revealLibraryTapped))
        revealButton.bezelStyle = .inline

        let buttons = NSStackView(views: [openButton, addButton, revealButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(18, after: subtitle)
        stack.addArrangedSubview(heading("Wallpaper Library"))
        stack.addArrangedSubview(packCountLabel)
        stack.addArrangedSubview(libraryPathLabel)
        stack.addArrangedSubview(buttons)
        stack.addArrangedSubview(caption(
            "Packs are referenced in place; adding a folder does not copy it. "
            + "Tangent lives in the menu bar — use the sparkles icon to change, pause or stop the wallpaper."
        ))
        return root
    }

    // MARK: - Playback

    private func playbackPane() -> NSView {
        let (root, stack) = makePane()

        fullscreenButton = NSButton(
            checkboxWithTitle: "Pause while a fullscreen app is in front",
            target: self,
            action: #selector(policyChanged)
        )
        batteryButton = NSButton(
            checkboxWithTitle: "Pause on battery power",
            target: self,
            action: #selector(policyChanged)
        )
        lockButton = NSButton(
            checkboxWithTitle: "Pause when the screen locks",
            target: self,
            action: #selector(policyChanged)
        )

        stack.addArrangedSubview(heading("Playback Rules"))
        stack.addArrangedSubview(caption(
            "These rules apply to every display. Playback resumes only when all active reasons have cleared, "
            + "so closing a fullscreen app will not undo a manual pause."
        ))
        stack.addArrangedSubview(fullscreenButton)
        stack.addArrangedSubview(batteryButton)
        stack.addArrangedSubview(lockButton)
        stack.addArrangedSubview(caption(
            "A manual Pause from the menu is independent of these rules."
        ))
        return root
    }

    // MARK: - Shortcuts

    private func shortcutsPane() -> NSView {
        let (root, stack) = makePane()

        hotkeyToggle = NSButton(
            checkboxWithTitle: "Enable global shortcuts",
            target: self,
            action: #selector(hotkeysToggled)
        )

        hotkeyStatusLabel = NSTextField(wrappingLabelWithString: "")
        hotkeyStatusLabel.font = .systemFont(ofSize: 11)

        stack.addArrangedSubview(heading("Global Shortcuts"))
        stack.addArrangedSubview(caption(
            "Work while another app is frontmost. Click a shortcut, then press a new combination — "
            + "Escape cancels and Delete restores the default. Carbon hot keys need no Accessibility "
            + "or Input Monitoring permission."
        ))
        stack.addArrangedSubview(hotkeyToggle)

        let grid = NSGridView()
        grid.rowSpacing = 9
        grid.columnSpacing = 22
        for action in HotkeyManager.Action.allCases {
            let name = NSTextField(labelWithString: action.title)
            name.font = .systemFont(ofSize: 12)

            let shortcut = NSButton(
                title: hotkeys.binding(for: action).display,
                target: self,
                action: #selector(beginRecording(_:))
            )
            shortcut.tag = Int(action.identifier)
            shortcut.bezelStyle = .rounded
            shortcut.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            shortcut.toolTip = "Click, then press a new combination"
            shortcut.translatesAutoresizingMaskIntoConstraints = false
            shortcut.widthAnchor.constraint(equalToConstant: 118).isActive = true
            shortcut.heightAnchor.constraint(equalToConstant: 24).isActive = true
            hotkeyButtons[action] = shortcut

            grid.addRow(with: [name, shortcut])
        }
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing

        bindingMessageLabel = NSTextField(wrappingLabelWithString: "")
        bindingMessageLabel.font = .systemFont(ofSize: 11)
        bindingMessageLabel.isHidden = true

        let resetAll = NSButton(
            title: "Reset All Shortcuts",
            target: self,
            action: #selector(resetAllShortcuts)
        )
        resetAll.bezelStyle = .inline

        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(bindingMessageLabel)
        stack.addArrangedSubview(resetAll)
        stack.addArrangedSubview(hotkeyStatusLabel)
        return root
    }

    // MARK: - About

    private func aboutPane() -> NSView {
        let (root, stack) = makePane()

        let title = NSTextField(labelWithString: "Tangent")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let version = NSTextField(labelWithString: "Version \(Self.versionString)")
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor

        let rows = NSGridView()
        rows.rowSpacing = 7
        rows.columnSpacing = 18
        rows.addRow(with: [Self.aboutKey("Bundle"), Self.aboutValue(Bundle.main.bundleIdentifier ?? "app.tangent.wallpaper")])
        rows.addRow(with: [Self.aboutKey("Architecture"), Self.aboutValue(Self.architecture)])
        rows.addRow(with: [Self.aboutKey("Minimum macOS"), Self.aboutValue("13.0")])
        rows.addRow(with: [Self.aboutKey("Video"), Self.aboutValue("AVFoundation + libmpv (VP9, AV1, Matroska)")])
        rows.addRow(with: [Self.aboutKey("libmpv"), Self.aboutValue(Self.libmpvDescription)])
        rows.column(at: 0).xPlacement = .leading
        rows.column(at: 1).xPlacement = .leading

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(version)
        stack.setCustomSpacing(18, after: version)
        stack.addArrangedSubview(rows)
        stack.addArrangedSubview(caption(
            "Tangent is GPL-3.0. Bundled third-party licenses are in the app's "
            + "Resources/Licenses folder."
        ))
        return root
    }

    private static func aboutKey(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func aboutValue(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    // MARK: - Refresh / actions

    private func refresh() {
        let policy = playback.policy
        fullscreenButton?.state = policy.pauseOnFullscreen ? .on : .off
        batteryButton?.state = policy.pauseOnBattery ? .on : .off
        lockButton?.state = policy.pauseOnLock ? .on : .off

        hotkeyToggle?.state = hotkeys.isEnabled ? .on : .off
        refreshBindingButtons()
        refreshHotkeyStatus()

        let count = library.packs.count
        packCountLabel?.stringValue = "\(count) wallpaper\(count == 1 ? "" : "s")"
        libraryPathLabel?.stringValue = PackLibrary.defaultRoot.path
        libraryPathLabel?.toolTip = PackLibrary.defaultRoot.path
    }

    private func refreshHotkeyStatus() {
        hotkeyStatusLabel?.stringValue = hotkeys.statusDescription
        hotkeyStatusLabel?.textColor = hotkeys.failures.isEmpty && hotkeys.isEnabled
            ? .secondaryLabelColor
            : (hotkeys.isEnabled ? .systemOrange : .secondaryLabelColor)
    }

    @objc private func policyChanged() {
        var policy = playback.policy
        policy.pauseOnFullscreen = fullscreenButton.state == .on
        policy.pauseOnBattery = batteryButton.state == .on
        policy.pauseOnLock = lockButton.state == .on
        playback.setPolicy(policy)
        onPolicyChange()
    }

    @objc private func hotkeysToggled() {
        hotkeys.isEnabled = hotkeyToggle.state == .on
        refreshHotkeyStatus()
        onHotkeysChange()
    }

    // MARK: - Shortcut recorder

    private func refreshBindingButtons() {
        guard recordingAction == nil else { return }
        for action in HotkeyManager.Action.allCases {
            guard let button = hotkeyButtons[action] else { continue }
            button.title = hotkeys.binding(for: action).display
            button.toolTip = hotkeys.isCustomized(action)
                ? "Custom shortcut — click to change"
                : "Default shortcut — click to change"
        }
    }

    @objc private func beginRecording(_ sender: NSButton) {
        guard let action = HotkeyManager.Action.action(for: UInt32(sender.tag)) else { return }
        finishRecording()

        recordingAction = action
        for button in hotkeyButtons.values { button.isEnabled = false }
        sender.isEnabled = true
        sender.title = "Press keys…"

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

    @objc private func resetAllShortcuts() {
        finishRecording()
        hotkeys.resetAllBindings()
        refreshHotkeyStatus()
        onHotkeysChange()
        showBindingMessage("All shortcuts restored to defaults.", color: .secondaryLabelColor)
    }

    @objc private func openLibraryTapped() { onOpenLibrary() }
    @objc private func addWallpaperTapped() { onAddWallpaper() }
    @objc private func revealLibraryTapped() { onRevealLibrary() }

    // MARK: - Static metadata

    private static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static var libmpvDescription: String {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/libmpv.2.dylib")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return "Bundled with the app"
        }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib") {
            return "External (Homebrew)"
        }
        return "Not installed"
    }
}
