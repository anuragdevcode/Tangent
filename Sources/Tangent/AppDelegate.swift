import AppKit
import UniformTypeIdentifiers

/// Menu-bar controller: the app shell and status-item surface, while
/// `WallpaperEngine` is the desktop core.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu?
    private let engine = WallpaperEngine()
    private let store = WallpaperStore()
    private let playback = PlaybackMonitor()
    private var libraryModel: LibraryModel!
    private var libraryWindow: LibraryWindowController!
    private var controlPanel: ControlPanelController?
    private let hotkeys = HotkeyManager()
    private var settingsWindow: SettingsWindowController?
    private var aboutWindow: AboutWindowController?
    private var popover: MenuBarPopoverController!
    private var actions: AppActions!

    /// Set from the command line for scripted use and verification.
    var initialConfig: WallpaperConfig?
    var initialPack: Pack?
    /// 1-based display index from `--display`, resolved once screens exist.
    var initialDisplayIndex: Int?
    var openLibraryOnLaunch = false
    /// `--snapshot-library <png>`: render the library window to a file, then quit.
    var snapshotPath: String?
    /// `--snapshot-properties <png>`: render the control panel, then quit.
    var snapshotPropertiesPath: String?
    /// `--snapshot-settings <png>`: render the settings window, then quit.
    var snapshotSettingsPath: String?
    /// `--snapshot-popover <png>`: render the menu bar popover, then quit.
    var snapshotPopoverPath: String?
    /// `--settings-pane N`: open Settings on a specific pane (for snapshots).
    var settingsPaneIndex: Int?
    /// `--gallery-search <text>` / `--gallery-select N`: snapshot helpers.
    var gallerySearch: String?
    var gallerySelectionIndex: Int?
    /// `--library-section N`: open the main window on a specific section.
    var librarySectionIndex: Int?
    /// `--report-frames <seconds>`: print libmpv frame counters, then quit.
    var frameReportDelay: Double?
    /// Set by `--ephemeral` for scripted runs that must not replace the user's
    /// saved wallpaper.
    var persistSelection = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkles.tv",
            accessibilityDescription: "Tangent"
        )
        statusItem.button?.toolTip = "Tangent"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        libraryModel = LibraryModel()
        actions = makeActions()
        popover = MenuBarPopoverController(actions: actions)
        engine.onChange = { [weak self] in self?.engineDidChange() }

        playback.onPause = { [weak self] reason in self?.engine.pause(reason) }
        playback.onResume = { [weak self] reason in self?.engine.resume(reason) }
        playback.start()

        hotkeys.onAction = { [weak self] action in self?.performHotkey(action) }
        hotkeys.start()

        rebuildMenu()

        if let snapshotSettingsPath {
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }
                self.writeSnapshot(of: self.settingsWindow?.window, to: snapshotSettingsPath)
                self.finishScriptedRun()
            }
            return
        }

        if openLibraryOnLaunch {
            showLibrary()
            if let snapshotPath {
                // Give AppKit a couple of frames to lay out and draw the window
                // before capturing it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self else { return }
                    self.writeSnapshot(of: self.libraryWindow?.window, to: snapshotPath)
                    self.finishScriptedRun()
                }
                return
            }
        }

        if let initialPack {
            apply(initialPack)
            if let initialDisplayIndex,
               let config = engine.layout.defaultConfig,
               initialDisplayIndex >= 1,
               initialDisplayIndex <= NSScreen.screens.count {
                let screen = NSScreen.screens[initialDisplayIndex - 1]
                engine.pin(config, for: DisplayIdentity.id(of: screen))
                persistLayout()
            }
            if snapshotPopoverPath != nil {
                schedulePopoverSnapshot()
                return
            }
            if let snapshotPropertiesPath {
                showProperties()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self else { return }
                    self.writeSnapshot(of: self.controlPanel?.window, to: snapshotPropertiesPath)
                    self.finishScriptedRun()
                }
            }
            if let frameReportDelay {
                DispatchQueue.main.asyncAfter(deadline: .now() + frameReportDelay) { [weak self] in
                    guard let self else { return }
                    let report = self.engine.mpvFrameReport
                    let payload: [String: Any] = [
                        "frames": report.frames,
                        "codecs": report.codecs,
                        "errors": report.errors,
                    ]
                    if let data = try? JSONSerialization.data(
                        withJSONObject: payload,
                        options: [.sortedKeys]
                    ), let text = String(data: data, encoding: .utf8) {
                        print(text)
                    }
                    self.finishScriptedRun()
                }
            }
            return
        }
        if let initialConfig {
            engine.start(config: initialConfig)
            rebuildMenu()
            return
        }

        if let saved = store.load() {
            if saved.hasPlayableConfig {
                engine.start(layout: saved)
            } else {
                // Everything in the saved layout was deleted or moved.
                store.clear()
            }
            rebuildMenu()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.engine.hasWallpaper else { return }
            self.engine.rebuildForScreens()
            self.rebuildMenu()
        }

        // Decoding is validated asynchronously; retry through libmpv before
        // reporting a failure, so AV1-in-MP4 and mislabelled files still play.
        NotificationCenter.default.addObserver(
            forName: .tangentVideoUnplayable,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let path = note.userInfo?["path"] as? String
            if let path, FileManager.default.fileExists(atPath: path) {
                self.engine.retryWithMPV(url: URL(fileURLWithPath: path))
                return
            }
            self.alert(
                "Video cannot be decoded",
                "\(path ?? "The selected file") could not be opened by AVFoundation or libmpv."
            )
        }

        NotificationCenter.default.addObserver(
            forName: .tangentMPVFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let path = note.userInfo?["path"] as? String
            self?.alert(
                "Video cannot be decoded",
                "\(path ?? "The selected video") could not be decoded by libmpv. Check that the file is complete and uses a supported codec."
            )
        }

        NotificationCenter.default.addObserver(
            forName: .tangentMPVUnavailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.alert(
                "libmpv is not available",
                "This wallpaper uses VP9/WebM, AV1 or Matroska, which need libmpv. Install it with `brew install mpv`, then apply the wallpaper again. H.264/HEVC wallpapers keep working without it."
            )
        }

        if snapshotPopoverPath != nil {
            schedulePopoverSnapshot()
        }
    }

    /// `--snapshot-popover`: show the popover, let it size itself, then capture
    /// its content view. The popover has no window of its own to snapshot
    /// through, so the view is rendered directly.
    private func schedulePopoverSnapshot() {
        guard let path = snapshotPopoverPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.popover.show(relativeTo: button)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.writeSnapshot(of: self.popover.view, to: path)
                self.finishScriptedRun()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        playback.stop()
        hotkeys.stop()
        engine.stop()
    }

    // MARK: - Interface actions

    /// Everything the AppKit interface can ask the app shell to do. The windows
    /// stay independent of the engine by talking through these closures.
    private func makeActions() -> AppActions {
        var actions = AppActions()
        actions.snapshot = { [weak self] in self?.makeSnapshot() ?? AppSnapshot() }

        actions.apply = { [weak self] pack in self?.apply(pack) }
        actions.applyToAllScreens = { [weak self] pack in
            guard let self else { return }
            self.engine.resetOverrides()
            self.apply(pack)
        }
        actions.setForThisScreen = { [weak self] pack in self?.setForCurrentScreen(pack) }
        actions.reveal = { pack in
            NSWorkspace.shared.activateFileViewerSelecting([pack.libraryEntry])
        }
        actions.duplicate = { [weak self] pack in
            _ = self?.libraryModel.duplicate(pack)
        }
        actions.removeFromLibrary = { [weak self] pack in
            self?.libraryModel.hide(pack)
        }
        actions.addWallpaper = { [weak self] in self?.pickWallpaperToAdd() }
        actions.scanFolder = { [weak self] in self?.pickFolderToScan() }
        actions.revealLibraryFolder = { [weak self] in self?.libraryModel.revealLibraryFolder() }
        actions.restoreHidden = { [weak self] in self?.libraryModel.restoreHidden() }
        actions.openLibrary = { [weak self] in self?.showLibrary() }
        actions.openLibrarySection = { [weak self] section in self?.showLibrarySection(section) }

        actions.togglePause = { [weak self] in self?.togglePause() }
        actions.nextWallpaper = { [weak self] in self?.nextWallpaper() }
        actions.stop = { [weak self] in self?.stopWallpaper() }
        actions.setMuted = { [weak self] muted in
            self?.engine.setMuted(muted)
            self?.rebuildMenu()
        }
        actions.setPolicy = { [weak self] policy in
            self?.playback.setPolicy(policy)
            self?.rebuildMenu()
        }
        actions.setHotkeysEnabled = { [weak self] enabled in
            guard let self else { return }
            self.hotkeys.isEnabled = enabled
            self.settingsWindow?.reload()
            self.rebuildMenu()
        }

        actions.useDefaultForDisplay = { [weak self] id in
            self?.engine.useDefault(for: id)
        }
        actions.pinCurrentToDisplay = { [weak self] id in
            guard let self, let config = self.engine.layout.defaultConfig else { return }
            self.engine.pin(config, for: id)
        }
        actions.turnOffDisplay = { [weak self] id in
            self?.engine.disable(id)
        }
        actions.resetDisplayOverrides = { [weak self] in
            self?.engine.resetOverrides()
        }

        actions.openSettings = { [weak self] in self?.showSettings() }
        actions.openAbout = { [weak self] in self?.showAbout() }
        actions.openProperties = { [weak self] pack in self?.showPropertiesFor(pack) }
        actions.quit = { NSApp.terminate(nil) }
        return actions
    }

    private func makeSnapshot() -> AppSnapshot {
        var snapshot = AppSnapshot()
        snapshot.isPaused = engine.isPaused
        snapshot.pauseReasons = engine.pauseReasons
        snapshot.isMuted = engine.isMuted
        snapshot.defaultConfig = engine.layout.defaultConfig
        snapshot.currentPack = currentLibraryPack()
        snapshot.policy = playback.policy
        snapshot.packCount = libraryModel?.packs.count ?? 0
        snapshot.hiddenCount = libraryModel?.hiddenCount ?? 0
        snapshot.favorites = libraryModel?.favorites ?? []
        snapshot.hotkeysEnabled = hotkeys.isEnabled
        snapshot.hotkeyStatus = hotkeys.statusDescription
        snapshot.statusDescription = engine.statusDescription
        snapshot.activeConfigs = engine.activeConfigs
        snapshot.displays = NSScreen.screens.map { screen in
            let id = DisplayIdentity.id(of: screen)
            let key = DisplayIdentity.key(id)
            return DisplaySummary(
                id: id,
                label: DisplayIdentity.label(for: screen),
                isMain: screen == NSScreen.main,
                config: engine.layout.config(for: id),
                isPinned: engine.layout.pins[key] != nil,
                isDisabled: engine.layout.disabled.contains(key)
            )
        }
        return snapshot
    }

    /// Changes made by the engine are saved and mirrored in the interface.
    private func engineDidChange() {
        if persistSelection, engine.hasWallpaper {
            store.save(engine.layout)
        }
        rebuildMenu()
        // The library inspector, the popover and the Settings playback card all
        // read the engine snapshot; refresh the ones on screen so none can show
        // the previous wallpaper after a switch. Closed windows refresh when
        // they are presented again.
        if libraryWindow?.window?.isVisible == true {
            libraryWindow?.refresh()
        }
        if popover?.isShown == true {
            popover?.reload()
        }
        if settingsWindow?.window?.isVisible == true {
            settingsWindow?.reload()
        }
    }

    /// Applies a wallpaper to the display under the pointer (the screen the
    /// menu bar belongs to, in practice), falling back to the main display.
    private func setForCurrentScreen(_ pack: Pack) {
        guard let config = WallpaperConfig(pack: pack) else {
            alert("Cannot use this wallpaper", "\(PackFormat.infoFile) does not resolve to a playable file.")
            return
        }

        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        if engine.layout.defaultConfig == nil {
            engine.start(config: config)
        } else {
            engine.pin(config, for: DisplayIdentity.id(of: screen))
        }
        persistLayout()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: engine.statusDescription, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(makeItem("Library…", #selector(showLibrary), key: "l"))
        menu.addItem(makeItem("Open Wallpaper…", #selector(openWallpaper), key: "o"))

        if engine.hasWallpaper {
            menu.addItem(.separator())
            menu.addItem(makeItem(engine.isPaused ? "Resume" : "Pause", #selector(togglePause)))
            menu.addItem(makeItem("Next Wallpaper", #selector(nextWallpaperAction)))
            let properties = makeItem("Wallpaper Properties…", #selector(showProperties), key: "p")
            properties.isEnabled = propertiesTarget(for: nil) != nil
            menu.addItem(properties)
            menu.addItem(makeItem("Stop", #selector(stopWallpaper)))
        }

        menu.addItem(.separator())
        menu.addItem(displaysMenu())
        menu.addItem(playbackMenu())
        menu.addItem(hotkeysMenu())

        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(showSettings), key: ","))
        menu.addItem(makeItem("Quit Tangent", #selector(quit), key: "q"))

        statusMenu = menu
        if popover?.isShown == true {
            popover.reload()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover?.close()
            guard let menu = statusMenu else { return }
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
            return
        }
        popover?.show(relativeTo: sender)
    }

    /// Per-display assignment. Each screen gets a submenu so a different
    /// wallpaper can run on each one.
    private func displaysMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for screen in NSScreen.screens {
            let displayID = DisplayIdentity.id(of: screen)
            let key = DisplayIdentity.key(displayID)
            let pinned = engine.layout.pins[key]
            let isDisabled = engine.layout.disabled.contains(key)
            let resolved = engine.layout.config(for: displayID)

            let state = resolved?.title ?? "Off"
            let item = NSMenuItem(
                title: "\(DisplayIdentity.label(for: screen)) — \(state)",
                action: nil,
                keyEquivalent: ""
            )
            let screenMenu = NSMenu()

            let useDefault = NSMenuItem(
                title: "Use Default Wallpaper",
                action: #selector(useDefaultForDisplay(_:)),
                keyEquivalent: ""
            )
            useDefault.target = self
            useDefault.representedObject = NSNumber(value: displayID)
            useDefault.state = (!isDisabled && pinned == nil) ? .on : .off
            screenMenu.addItem(useDefault)

            let pin = NSMenuItem(
                title: "Pin Current Wallpaper Here",
                action: #selector(pinCurrentToDisplay(_:)),
                keyEquivalent: ""
            )
            pin.target = self
            pin.representedObject = NSNumber(value: displayID)
            pin.state = pinned != nil ? .on : .off
            pin.isEnabled = engine.layout.defaultConfig != nil
            pin.toolTip = engine.layout.defaultConfig.map { "Pin “\($0.title)” to this display" }
            screenMenu.addItem(pin)

            screenMenu.addItem(.separator())

            let off = NSMenuItem(
                title: "Turn Off This Display",
                action: #selector(turnOffDisplay(_:)),
                keyEquivalent: ""
            )
            off.target = self
            off.representedObject = NSNumber(value: displayID)
            off.state = isDisabled ? .on : .off
            screenMenu.addItem(off)

            item.submenu = screenMenu
            item.toolTip = resolved.map { "\($0.type.displayName) · \($0.title)" }
            submenu.addItem(item)
        }

        if engine.layout.hasPins {
            submenu.addItem(.separator())
            submenu.addItem(makeItem("Reset Per-Display Layout", #selector(resetDisplayOverrides)))
        }

        submenu.addItem(.separator())
        let note = NSMenuItem(
            title: "Each display runs its own window; one wallpaper cannot span displays.",
            action: nil,
            keyEquivalent: ""
        )
        note.isEnabled = false
        submenu.addItem(note)

        parent.submenu = submenu
        return parent
    }

    private func playbackMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Playback Rules", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let policy = playback.policy
        submenu.addItem(policyItem(
            "Pause for fullscreen apps",
            #selector(toggleFullscreenRule),
            on: policy.pauseOnFullscreen
        ))
        submenu.addItem(policyItem(
            "Pause on battery power",
            #selector(toggleBatteryRule),
            on: policy.pauseOnBattery
        ))
        submenu.addItem(policyItem(
            "Pause when screen locks",
            #selector(toggleLockRule),
            on: policy.pauseOnLock
        ))

        parent.submenu = submenu
        return parent
    }

    private func policyItem(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    /// Shows the global shortcuts and whether each one registered. The items
    /// are informational; the Settings pane owns the on/off switch.
    private func hotkeysMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Hotkeys", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let toggle = NSMenuItem(
            title: "Enable Global Shortcuts",
            action: #selector(toggleHotkeys),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = hotkeys.isEnabled ? .on : .off
        submenu.addItem(toggle)
        submenu.addItem(.separator())

        for action in HotkeyManager.Action.allCases {
            let custom = hotkeys.isCustomized(action) ? "  (custom)" : ""
            let item = NSMenuItem(
                title: "\(action.title)    \(hotkeys.binding(for: action).display)\(custom)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            item.state = hotkeys.registeredActions.contains(action) ? .on : .off
            submenu.addItem(item)
        }

        if hotkeys.isEnabled, !hotkeys.failures.isEmpty {
            submenu.addItem(.separator())
            let note = NSMenuItem(title: hotkeys.statusDescription, action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        }

        parent.submenu = submenu
        return parent
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func showLibrary() {
        if libraryWindow == nil {
            libraryWindow = LibraryWindowController(model: libraryModel, actions: actions)
        }
        libraryWindow.present()
        libraryWindow.prepareForSnapshot(
            search: gallerySearch,
            selection: gallerySelectionIndex
        )
        if let librarySectionIndex {
            libraryWindow.selectSectionForSnapshot(librarySectionIndex)
        }
    }

    private func showLibrarySection(_ section: LibrarySection) {
        showLibrary()
        libraryWindow.showSection(section)
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            aboutWindow = AboutWindowController()
        }
        aboutWindow?.present()
    }

    // MARK: - Settings and hotkeys

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                actions: actions,
                hotkeys: hotkeys,
                onHotkeysChange: { [weak self] in self?.rebuildMenu() }
            )
        }
        settingsWindow?.present()
        if let settingsPaneIndex {
            settingsWindow?.selectPane(settingsPaneIndex)
        }
    }

    @objc private func toggleHotkeys() {
        hotkeys.isEnabled.toggle()
        settingsWindow?.reload()
        rebuildMenu()
    }

    private func performHotkey(_ action: HotkeyManager.Action) {
        switch action {
        case .togglePause:
            guard engine.hasWallpaper else { return }
            togglePause()
        case .nextWallpaper:
            nextWallpaper()
        case .openLibrary:
            showLibrary()
        case .stopWallpaper:
            guard engine.hasWallpaper else { return }
            stopWallpaper()
        }
    }

    @objc private func nextWallpaperAction() {
        nextWallpaper()
    }

    /// Cycles through the library's playable wallpapers, starting from whichever
    /// one is currently the default. Unsupported packs are skipped.
    private func nextWallpaper() {
        guard let next = WallpaperCycler.next(
            after: currentLibraryPack(),
            in: libraryModel.packs
        ) else {
            alert(
                "No wallpapers to switch to",
                "Add a playable wallpaper to the library first."
            )
            return
        }
        apply(next)
    }

    /// Matches the active default config back to its library tile by entry path,
    /// which also works for bare files added to the library.
    private func currentLibraryPack() -> Pack? {
        guard let config = engine.layout.defaultConfig else { return nil }
        let current = config.entryURL.standardizedFileURL.path
        return libraryModel.packs.first {
            $0.entryURL?.standardizedFileURL.path == current
        }
    }

    // MARK: - Wallpaper properties

    /// The controls for a specific pack when one is given, otherwise the first
    /// web wallpaper on screen that defines controls. Panels are per-pack; with
    /// several web displays this picks the first one in screen order, which
    /// matches what the user sees as "the wallpaper".
    private func propertiesTarget(
        for pack: Pack?
    ) -> (config: WallpaperConfig, controls: [PropertyControl])? {
        let configs = engine.activeConfigs.map(\.config)
        let ordered: [WallpaperConfig]
        if let pack, let entry = pack.entryURL?.standardizedFileURL.path {
            ordered = configs.filter { $0.entryURL.standardizedFileURL.path == entry }
                + configs.filter { $0.entryURL.standardizedFileURL.path != entry }
        } else {
            ordered = configs
        }

        for config in ordered {
            guard [.web, .webaudio, .url].contains(config.type),
                  let root = config.root
            else { continue }
            let controls = PropertyStore.shared.controls(forRoot: root)
            if !controls.isEmpty {
                return (config, controls)
            }
        }
        return nil
    }

    @objc private func showProperties() {
        showPropertiesFor(nil)
    }

    private func showPropertiesFor(_ pack: Pack?) {
        guard let target = propertiesTarget(for: pack), let root = target.config.root else {
            alert(
                "No wallpaper properties",
                "The active wallpaper has no property controls."
            )
            return
        }

        controlPanel?.close()
        let panel = ControlPanelController(
            title: target.config.title,
            controls: target.controls,
            root: root,
            onChange: { [weak self] name, value in
                self?.engine.broadcastProperty(name: name, value: value, root: root)
            },
            onReset: { [weak self] in
                self?.resetProperties(for: target.config)
            }
        )
        controlPanel = panel
        panel.present()
    }

    /// Deletes the customised copy, then pushes the pack's own defaults to the
    /// live page so the reset is visible immediately.
    private func resetProperties(for config: WallpaperConfig) {
        guard let root = config.root else { return }
        PropertyStore.shared.reset(root: root)

        let defaults = PackProperties.load(folder: root)
        for binding in PackProperties.bridgeBindings(for: defaults, rootFolder: root) {
            engine.broadcastProperty(name: binding.name, value: binding.value, root: root)
        }

        controlPanel?.close()
        controlPanel = nil
        showProperties()
    }

    @objc private func openWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "Open a wallpaper"
        panel.message = "Choose a wallpaper folder or a video, image, GIF, or web file."
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url, trackInLibrary: true)
    }

    private func pickWallpaperToAdd() {
        let panel = NSOpenPanel()
        panel.title = "Add wallpapers to library"
        panel.message = "Choose videos, images, GIFs, web pages or wallpaper packs. You can select more than one."
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        libraryModel.add(contentsOf: panel.urls)
        libraryWindow?.showAllWallpapers()
    }

    private func pickFolderToScan() {
        let panel = NSOpenPanel()
        panel.title = "Scan a folder for wallpapers"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryModel.add(url)
    }

    private func open(url: URL, trackInLibrary: Bool) {
        guard let pack = Pack.synthetic(fileURL: url) else {
            alert(
                "Not a wallpaper",
                "That item is not a wallpaper pack or a supported video, image, GIF, or web folder."
            )
            return
        }
        if trackInLibrary {
            libraryModel.add(pack.libraryEntry)
        }
        apply(pack)
    }

    private func apply(_ pack: Pack) {
        if let reason = pack.unsupportedReason {
            alert("Cannot use this wallpaper", reason)
            return
        }
        guard let config = WallpaperConfig(pack: pack) else {
            alert("Cannot use this wallpaper", "\(PackFormat.infoFile) does not resolve to a playable file.")
            return
        }

        engine.start(config: config)
        guard engine.activeDisplayCount > 0 else {
            alert(
                "Could not start wallpaper",
                "No display accepted the wallpaper. The file may use a codec AVFoundation cannot decode (see ARCHITECTURE.md)."
            )
            return
        }

        controlPanel?.close()
        controlPanel = nil
        persistLayout()
    }

    // MARK: - Displays

    @objc private func useDefaultForDisplay(_ sender: NSMenuItem) {
        guard let id = displayID(from: sender) else { return }
        engine.useDefault(for: id)
        persistLayout()
    }

    @objc private func pinCurrentToDisplay(_ sender: NSMenuItem) {
        guard let id = displayID(from: sender),
              let config = engine.layout.defaultConfig
        else { return }
        engine.pin(config, for: id)
        persistLayout()
    }

    @objc private func turnOffDisplay(_ sender: NSMenuItem) {
        guard let id = displayID(from: sender) else { return }
        engine.disable(id)
        persistLayout()
    }

    @objc private func resetDisplayOverrides() {
        engine.resetOverrides()
        persistLayout()
    }

    private func displayID(from item: NSMenuItem) -> CGDirectDisplayID? {
        (item.representedObject as? NSNumber)?.uint32Value
    }

    /// Saves after any layout change and refreshes the menu so checkmarks and
    /// status text always match what is on screen.
    private func persistLayout() {
        if persistSelection, engine.hasWallpaper {
            store.save(engine.layout)
        }
        rebuildMenu()
    }

    @objc private func togglePause() {
        if engine.isPaused { engine.resume(.user) } else { engine.pause(.user) }
        rebuildMenu()
    }

    @objc private func stopWallpaper() {
        engine.stop()
        store.clear()
        controlPanel?.close()
        controlPanel = nil
        rebuildMenu()
    }

    @objc private func toggleFullscreenRule() {
        var policy = playback.policy
        policy.pauseOnFullscreen.toggle()
        playback.setPolicy(policy)
        rebuildMenu()
    }

    @objc private func toggleBatteryRule() {
        var policy = playback.policy
        policy.pauseOnBattery.toggle()
        playback.setPolicy(policy)
        rebuildMenu()
    }

    @objc private func toggleLockRule() {
        var policy = playback.policy
        policy.pauseOnLock.toggle()
        playback.setPolicy(policy)
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func alert(_ message: String, _ informative: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Scripted runs (snapshots, frame reports) must end even if a window or a
    /// media backend is still winding down. `NSApp.terminate` waits for those.
    private func finishScriptedRun() -> Never {
        fflush(stdout)
        fflush(stderr)
        exit(0)
    }

    /// Renders the library window into a PNG using AppKit's own drawing path.
    /// Unlike `screencapture`, this needs no Screen Recording permission, so the
    /// UI can be verified in scripted runs.
    ///
    /// The content view is not opaque, so the window background is painted into
    /// the bitmap first; otherwise dark-mode text would be invisible on the
    /// transparent (white-rendered) areas.
    private func writeSnapshot(of window: NSWindow?, to path: String) {
        guard let view = window?.contentView else {
            FileHandle.standardError.write(Data("snapshot: no window\n".utf8))
            return
        }
        writeSnapshot(of: view, to: path)
    }

    private func writeSnapshot(of view: NSView?, to path: String) {
        guard let view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            FileHandle.standardError.write(Data("snapshot: no view\n".utf8))
            return
        }

        // Start from an opaque canvas: the window is opaque, so anything the
        // view tree leaves untouched should read as canvas, not as a hole.
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            Theme.canvas.setFill()
            view.bounds.fill()
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }

        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: PNG encoding failed\n".utf8))
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("snapshot: wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
        }
    }
}
