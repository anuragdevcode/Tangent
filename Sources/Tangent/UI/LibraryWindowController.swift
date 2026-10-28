import AppKit

/// The main window: a source-list sidebar, an adaptive gallery, and a
/// collapsible inspector. Built on `NSVisualEffectView` materials and native
/// controls so it follows the system appearance, accent color and accessibility
/// settings.
final class LibraryWindowController: NSWindowController,
    NSWindowDelegate,
    NSToolbarDelegate,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSSearchFieldDelegate {

    // MARK: - Model

    private let model: LibraryModel
    private let actions: AppActions

    private var snapshot = AppSnapshot()
    private var selectedSection: LibrarySection = .all
    private var selectedPack: Pack?
    private var restoringSelection = false
    private var snapshotSelection: Int?

    // MARK: - Views

    private var sidebar: NSVisualEffectView!
    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarSeparator: HairlineView!
    private var navStack: NSStackView!
    private var searchField: NSSearchField!
    private var navRows: [LibrarySection: SidebarRowView] = [:]

    private var contentArea: NSView!
    private var headerView: NSView!
    private var pageTitle: NSTextField!
    private var pageSubtitle: NSTextField!
    private var statusPill: StatusPillView!

    private var collectionView: GalleryCollectionView!
    private var gridLayout: NSCollectionViewFlowLayout!
    private var gridScroll: NSScrollView!
    private var emptyHost: NSView!
    private var hintBar: NSView!

    private var pageHost: NSView!
    private var currentPage: NSView?

    private var inspector: NSView!
    private var inspectorWidth: NSLayoutConstraint!
    private var inspectorSeparator: HairlineView!
    private var inspectorView: WallpaperInspectorView!

    private var toast: ToastView?
    private var toastWorkItem: DispatchWorkItem?

    private var isInspectorVisible = true
    private var inspectorPreferredVisible = true
    private var isSidebarVisible = true

    private var visiblePacks: [Pack] {
        var packs = model.query.apply(to: model.packs)
        if selectedSection == .favorites {
            packs = packs.filter { model.isFavorite($0) }
        }
        return packs
    }

    // MARK: - Init

    init(model: LibraryModel, actions: AppActions) {
        self.model = model
        self.actions = actions

        let window = LibraryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tangent"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 660)
        window.center()
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)
        window.controller = self
        window.delegate = self

        buildWindow()
        model.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    deinit {
        toastWorkItem?.cancel()
    }

    // MARK: - Presentation

    func present() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Scripted snapshot helper (`--gallery-search`, `--gallery-select`).
    func prepareForSnapshot(search: String?, selection: Int?) {
        if let search {
            searchField.stringValue = search
            model.query.search = search
        }
        snapshotSelection = selection
        if let selection {
            let packs = visiblePacks
            guard packs.indices.contains(selection) else { return }
            select(pack: packs[selection])
        }
    }

    /// Switches to a section by index for snapshots (`--library-section N`).
    func selectSectionForSnapshot(_ index: Int) {
        guard let section = LibrarySection(rawValue: index) else { return }
        show(section: section)
    }

    /// Public entry point used by the menu bar and the Displays page.
    func showSection(_ section: LibrarySection) {
        show(section: section)
    }

    func windowWillClose(_ notification: Notification) {
        inspectorView?.stopPreview()
        if let toastWorkItem { toastWorkItem.cancel() }
    }

    func windowDidResize(_ notification: Notification) {
        updateGridMetrics()
    }

    // MARK: - Window construction

    private func buildWindow() {
        guard let content = window?.contentView else { return }

        // Sample the window's own background instead of the desktop: the gallery
        // window is a document window, and a live wallpaper behind it would tint
        // the inspector unpredictably.
        let canvas = CanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false

        sidebar = VisualEffectView(material: .sidebar, blending: .withinWindow)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        sidebarSeparator = HairlineView()
        sidebarSeparator.translatesAutoresizingMaskIntoConstraints = false

        contentArea = CanvasView()
        contentArea.translatesAutoresizingMaskIntoConstraints = false

        inspector = PaneView()
        inspector.translatesAutoresizingMaskIntoConstraints = false

        inspectorSeparator = HairlineView()
        inspectorSeparator.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(canvas)
        content.addSubview(sidebar)
        content.addSubview(sidebarSeparator)
        content.addSubview(contentArea)
        content.addSubview(inspector)
        content.addSubview(inspectorSeparator)

        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 232)
        inspectorWidth = inspector.widthAnchor.constraint(equalToConstant: 300)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarWidth,

            sidebarSeparator.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarSeparator.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarSeparator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarSeparator.widthAnchor.constraint(equalToConstant: 1),

            contentArea.topAnchor.constraint(equalTo: content.topAnchor),
            contentArea.leadingAnchor.constraint(equalTo: sidebarSeparator.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            inspector.topAnchor.constraint(equalTo: content.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            inspector.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            inspectorWidth,

            inspectorSeparator.topAnchor.constraint(equalTo: content.topAnchor),
            inspectorSeparator.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            inspectorSeparator.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),
            inspectorSeparator.widthAnchor.constraint(equalToConstant: 1),

            contentArea.trailingAnchor.constraint(equalTo: inspectorSeparator.leadingAnchor),
        ])

        buildSidebar()
        buildContent()
        buildInspector()
        buildToolbar()
    }

    // MARK: - Sidebar

    private func buildSidebar() {
        searchField = NSSearchField()
        searchField.placeholderString = "Search wallpapers"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.alignment = .leading
        navStack.spacing = 1
        navStack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(navStack)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(searchField)
        sidebar.addSubview(scroll)
        sidebar.pin(searchField, insets: NSEdgeInsets(top: 52, left: 12, bottom: 0, right: 12))
        // `pin` sets a bottom constraint we do not want for the search field.
        searchField.superview?.constraints
            .filter { $0.firstItem === searchField && $0.firstAttribute == .height }
            .forEach { $0.isActive = false }
        sidebar.constraints
            .filter {
                ($0.firstItem as? NSView) === searchField
                    && $0.firstAttribute == .bottom
            }
            .forEach { $0.isActive = false }
        NSLayoutConstraint.activate([
            searchField.heightAnchor.constraint(equalToConstant: 26),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -42),

            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            navStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            navStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 10),
            navStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -10),
            navStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
        ])

        buildNavigation()

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true

        let footerSeparator = HairlineView()
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false

        let settingsButton = IconButton(
            symbol: "gearshape",
            pointSize: 12,
            style: .quiet,
            toolTip: "Settings",
            target: self,
            action: #selector(openSettings)
        )
        let version = makeLabel(
            "Tangent \(Format.version())",
            font: Theme.tiny,
            color: .tertiaryLabelColor
        )
        let footerRow = hstack([settingsButton, version, flexibleSpacer()], spacing: 6)
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(footerSeparator)
        footer.addSubview(footerRow)
        sidebar.addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 42),

            footerSeparator.topAnchor.constraint(equalTo: footer.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),

            footerRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            footerRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            footerRow.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 3),
        ])
    }

    private func buildNavigation() {
        let groups: [(String, [LibrarySection])] = [
            ("Library", [.all, .favorites, .video, .web, .images]),
            ("System", [.displays, .automation]),
            ("About", [.about]),
        ]

        for (index, group) in groups.enumerated() {
            let header = makeSectionHeader(group.0)
            header.translatesAutoresizingMaskIntoConstraints = false
            navStack.addArrangedSubview(header)
            navStack.setCustomSpacing(5, after: header)
            header.leadingAnchor.constraint(equalTo: navStack.leadingAnchor, constant: 9).isActive = true
            header.heightAnchor.constraint(equalToConstant: 16).isActive = true

            for section in group.1 {
                let row = SidebarRowView(section: section)
                row.target = self
                row.action = #selector(navRowTapped(_:))
                row.tag = section.rawValue
                row.translatesAutoresizingMaskIntoConstraints = false
                navStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: navStack.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: 30).isActive = true
                navRows[section] = row
            }

            if index < groups.count - 1 {
                let spacer = spacing(10)
                navStack.addArrangedSubview(spacer)
            }
        }
    }

    // MARK: - Content

    private func buildContent() {
        headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false

        pageTitle = makeLabel("All Wallpapers", font: Theme.windowTitle)
        pageSubtitle = makeLabel("", font: Theme.caption, color: .secondaryLabelColor)
        statusPill = StatusPillView(text: "Live", tint: .systemGreen)
        statusPill.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = vstack([pageTitle, pageSubtitle], spacing: 3)
        let headerRow = hstack([titleStack, flexibleSpacer(), statusPill], spacing: 12)
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerRow)

        gridLayout = NSCollectionViewFlowLayout()
        gridLayout.itemSize = NSSize(width: 230, height: 208)
        gridLayout.sectionInset = NSEdgeInsets(top: 4, left: 22, bottom: 22, right: 22)
        gridLayout.minimumInteritemSpacing = 16
        gridLayout.minimumLineSpacing = 16

        collectionView = GalleryCollectionView()
        collectionView.collectionViewLayout = gridLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            WallpaperCardView.self,
            forItemWithIdentifier: WallpaperCardView.identifier
        )
        collectionView.onActivate = { [weak self] in self?.applySelected() }
        collectionView.onPreview = { [weak self] in
            guard let self else { return }
            if !self.isInspectorVisible { self.setInspector(visible: true) }
            self.inspectorView.togglePreview()
        }
        collectionView.setAccessibilityLabel("Wallpaper gallery")

        gridScroll = NSScrollView()
        gridScroll.drawsBackground = true
        gridScroll.backgroundColor = Theme.canvas
        gridScroll.contentView.drawsBackground = true
        gridScroll.contentView.backgroundColor = Theme.canvas
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.documentView = collectionView
        gridScroll.translatesAutoresizingMaskIntoConstraints = false

        emptyHost = NSView()
        emptyHost.translatesAutoresizingMaskIntoConstraints = false

        hintBar = NSView()
        hintBar.translatesAutoresizingMaskIntoConstraints = false
        let hintSeparator = HairlineView()
        hintSeparator.translatesAutoresizingMaskIntoConstraints = false
        let hint = makeLabel(
            "Double-click to apply   ·   Space for live preview",
            font: Theme.tiny,
            color: .tertiaryLabelColor
        )
        let keys = hstack(
            [KeyCapView("⌘1"), makeLabel("Library  ", font: Theme.tiny, color: .tertiaryLabelColor),
             KeyCapView("⌘2"), makeLabel("Displays", font: Theme.tiny, color: .tertiaryLabelColor)],
            spacing: 4
        )
        let hintRow = hstack([hint, flexibleSpacer(), keys], spacing: 8)
        hintRow.translatesAutoresizingMaskIntoConstraints = false
        hintBar.addSubview(hintSeparator)
        hintBar.addSubview(hintRow)

        pageHost = NSView()
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        pageHost.isHidden = true

        contentArea.addSubview(headerView)
        contentArea.addSubview(gridScroll)
        contentArea.addSubview(emptyHost)
        contentArea.addSubview(hintBar)
        contentArea.addSubview(pageHost)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 46),
            headerView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 68),

            headerRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            headerRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),
            headerRow.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -14),

            gridScroll.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            gridScroll.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: hintBar.topAnchor),

            emptyHost.topAnchor.constraint(equalTo: gridScroll.topAnchor),
            emptyHost.leadingAnchor.constraint(equalTo: gridScroll.leadingAnchor),
            emptyHost.trailingAnchor.constraint(equalTo: gridScroll.trailingAnchor),
            emptyHost.bottomAnchor.constraint(equalTo: gridScroll.bottomAnchor),

            hintBar.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            hintBar.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            hintBar.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            hintBar.heightAnchor.constraint(equalToConstant: 32),

            hintSeparator.topAnchor.constraint(equalTo: hintBar.topAnchor),
            hintSeparator.leadingAnchor.constraint(equalTo: hintBar.leadingAnchor),
            hintSeparator.trailingAnchor.constraint(equalTo: hintBar.trailingAnchor),

            hintRow.leadingAnchor.constraint(equalTo: hintBar.leadingAnchor, constant: 24),
            hintRow.trailingAnchor.constraint(equalTo: hintBar.trailingAnchor, constant: -24),
            hintRow.centerYAnchor.constraint(equalTo: hintBar.centerYAnchor, constant: 1),

            pageHost.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 46),
            pageHost.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            pageHost.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    // MARK: - Inspector

    private func buildInspector() {
        inspectorView = WallpaperInspectorView(
            actions: actions,
            onClose: { [weak self] in self?.setInspector(visible: false) },
            onToggleFavorite: { [weak self] pack in
                self?.model.toggleFavorite(pack)
            }
        )
        inspector.addSubview(inspectorView)
        inspector.pin(inspectorView)
    }

    // MARK: - Toolbar

    private enum ToolbarID {
        static let sidebar = NSToolbarItem.Identifier("tangent.sidebar")
        static let add = NSToolbarItem.Identifier("tangent.add")
        static let scan = NSToolbarItem.Identifier("tangent.scan")
        static let rescan = NSToolbarItem.Identifier("tangent.rescan")
        static let inspector = NSToolbarItem.Identifier("tangent.inspector")
    }

    private func buildToolbar() {
        let toolbar = NSToolbar(identifier: "tangent.library.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.sidebar, ToolbarID.add, ToolbarID.scan, ToolbarID.rescan, .flexibleSpace, ToolbarID.inspector]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.sidebar, .flexibleSpace, ToolbarID.add, ToolbarID.scan, ToolbarID.rescan, .flexibleSpace, ToolbarID.inspector]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .flexibleSpace {
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isBordered = true

        switch itemIdentifier {
        case ToolbarID.sidebar:
            item.label = "Sidebar"
            item.paletteLabel = "Sidebar"
            item.toolTip = "Show or hide the sidebar"
            item.image = Symbols.image("sidebar.leading", pointSize: 14)
            item.target = self
            item.action = #selector(toggleSidebar)
        case ToolbarID.add:
            item.label = "Add Wallpaper"
            item.paletteLabel = "Add Wallpaper"
            item.toolTip = "Add a wallpaper to the library"
            item.image = Symbols.image("plus", pointSize: 14)
            item.target = self
            item.action = #selector(addWallpaper)
        case ToolbarID.scan:
            item.label = "Scan Folder"
            item.paletteLabel = "Scan Folder"
            item.toolTip = "Scan a folder for wallpaper packs"
            item.image = Symbols.image("folder.badge.plus", pointSize: 14)
            item.target = self
            item.action = #selector(scanFolder)
        case ToolbarID.rescan:
            item.label = "Rescan"
            item.paletteLabel = "Rescan"
            item.toolTip = "Rescan library folders"
            item.image = Symbols.image("arrow.clockwise", pointSize: 13)
            item.target = self
            item.action = #selector(rescan)
        case ToolbarID.inspector:
            item.label = "Inspector"
            item.paletteLabel = "Inspector"
            item.toolTip = "Show or hide the inspector"
            item.image = Symbols.image("sidebar.trailing", pointSize: 14)
            item.target = self
            item.action = #selector(toggleInspector)
        default:
            return nil
        }
        return item
    }

    // MARK: - Refresh

    private func refresh() {
        snapshot = actions.snapshot()
        updateNavigationCounts()
        updateStatus(visible: selectedSection.isLibrary)

        if selectedSection.isLibrary {
            let packs = visiblePacks
            restoringSelection = true
            collectionView.reloadData()
            restoringSelection = false
            restoreSelection(packs)
            updateHeader(packs)
            updateEmptyState(packs)

            if let selection = snapshotSelection {
                snapshotSelection = nil
                if packs.indices.contains(selection) {
                    select(pack: packs[selection])
                }
            }
        } else {
            updateHeader(nil)
            rebuildCurrentPage()
        }

        updateInspector()
        updateGridMetrics()
    }

    private func updateNavigationCounts() {
        let packs = model.packs
        navRows[.all]?.setCount(packs.count)
        navRows[.favorites]?.setCount(packs.filter { model.isFavorite($0) }.count)
        navRows[.video]?.setCount(packs.filter { $0.info.type == .video }.count)
        navRows[.web]?.setCount(packs.filter { [.web, .webaudio, .url].contains($0.info.type) }.count)
        navRows[.images]?.setCount(packs.filter { [.gif, .picture].contains($0.info.type) }.count)
        for (section, row) in navRows {
            row.setSelected(section == selectedSection)
        }
    }

    private func updateHeader(_ packs: [Pack]?) {
        pageTitle.stringValue = selectedSection.title
        guard let packs else {
            pageSubtitle.stringValue = ""
            return
        }

        let total = model.packs.count
        let visible = packs.count
        let countText = visible == total
            ? Format.count(total, singular: "wallpaper")
            : "\(visible) of \(total) wallpapers"

        var subtitle = "\(countText) · referenced in place"
        if selectedSection == .favorites {
            subtitle = "\(countText) in favorites"
        }
        if !model.query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            subtitle += " · filtered"
        }
        pageSubtitle.stringValue = subtitle
    }

    private func updateStatus(visible: Bool) {
        statusPill.isHidden = !visible || snapshot.defaultConfig == nil
        guard visible, snapshot.defaultConfig != nil else { return }
        statusPill.configure(
            text: snapshot.isPaused ? "Paused" : "Live",
            tint: snapshot.isPaused ? .systemOrange : .systemGreen
        )
    }

    private func updateEmptyState(_ packs: [Pack]) {
        emptyHost.subviews.forEach { $0.removeFromSuperview() }
        guard packs.isEmpty else { return }

        let hasPacks = !model.packs.isEmpty
        let hasSearch = !model.query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let empty: EmptyStateView
        if selectedSection == .favorites, !hasSearch {
            empty = EmptyStateView(
                symbol: "star",
                title: "No Favorites Yet",
                message: "Star a wallpaper from its card or the inspector to keep it here.",
                actionTitle: "Browse Library",
                actionSymbol: "square.grid.2x2"
            ) { [weak self] in
                self?.show(section: .all)
            }
        } else if hasSearch {
            empty = EmptyStateView(
                symbol: "magnifyingglass",
                title: "No Wallpapers Match",
                message: "Try a different search, or clear it to see everything in this section.",
                actionTitle: "Clear Search",
                actionSymbol: "xmark.circle"
            ) { [weak self] in
                guard let self else { return }
                self.searchField.stringValue = ""
                self.model.query.search = ""
            }
        } else {
            empty = EmptyStateView(
                symbol: "sparkles.rectangle.stack",
                title: "Your Library Is Empty",
                message: hasPacks
                    ? "No wallpapers in this section."
                    : "Add a wallpaper pack folder, a video, a GIF, an image or a web page to get started.",
                actionTitle: "Add Wallpaper…",
                actionSymbol: "plus"
            ) { [weak self] in
                self?.actions.addWallpaper()
            }
        }

        emptyHost.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: emptyHost.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: emptyHost.centerYAnchor, constant: -10),
        ])
    }

    private func updateInspector() {
        inspectorView.update(
            pack: selectedPack,
            snapshot: snapshot,
            isFavorite: selectedPack.map { model.isFavorite($0) } ?? false
        )
    }

    private func updateGridMetrics() {
        guard let gridScroll else { return }
        let available = gridScroll.contentView.bounds.width
        guard available > 0 else { return }

        let inset: CGFloat = 22
        let spacing: CGFloat = 16
        let minimum: CGFloat = 188
        let maximum: CGFloat = 262

        let usable = available - inset * 2
        let columns = max(1, Int((usable + spacing) / (minimum + spacing)))
        let width = min(maximum, floor((usable - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
        let previewHeight = (width - 10) * 10.0 / 16.0
        let height = previewHeight + 64

        if abs(gridLayout.itemSize.width - width) > 0.5 || abs(gridLayout.itemSize.height - height) > 0.5 {
            gridLayout.itemSize = NSSize(width: width, height: height)
            gridLayout.invalidateLayout()
        }
    }

    private func restoreSelection(_ packs: [Pack]) {
        guard let identifier = selectedPack?.id,
              let index = packs.firstIndex(where: { $0.id == identifier })
        else {
            selectedPack = nil
            collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        selectedPack = packs[index]
    }

    private func select(pack: Pack?) {
        selectedPack = pack
        guard let pack,
              let index = visiblePacks.firstIndex(where: { $0.id == pack.id })
        else {
            collectionView.deselectAll(nil)
            updateInspector()
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
        updateInspector()
    }

    // MARK: - Sections and pages

    private func show(section: LibrarySection) {
        guard section != selectedSection else { return }

        selectedSection = section
        inspectorView.stopPreview()

        // Displays, Automation and About do not describe one wallpaper, so the
        // inspector steps aside. Returning to the library restores the user's
        // last choice instead of overriding it.
        setInspector(
            visible: section.isLibrary ? inspectorPreferredVisible : false,
            remember: false
        )

        if section.isLibrary {
            pageHost.isHidden = true
            currentPage?.removeFromSuperview()
            currentPage = nil
            headerView.isHidden = false
            gridScroll.isHidden = false
            hintBar.isHidden = false
            model.query.filter = section.filter ?? .all
            refresh()
        } else {
            headerView.isHidden = true
            gridScroll.isHidden = true
            hintBar.isHidden = true
            emptyHost.subviews.forEach { $0.removeFromSuperview() }
            pageHost.isHidden = false
            updateNavigationCounts()
            updateStatus(visible: false)
            rebuildCurrentPage()
            updateInspector()
        }

        // Swapping pages rebuilds the key-view loop, and AppKit hands focus to
        // the first field it finds: the sidebar search field. That leaves a
        // blinking insertion point in a field nobody clicked and hides the
        // placeholder behind the field editor.
        if !section.isLibrary,
           let editor = searchField.currentEditor(),
           window?.firstResponder === editor {
            window?.makeFirstResponder(nil)
        }
    }

    private func rebuildCurrentPage() {
        currentPage?.removeFromSuperview()
        currentPage = nil
        guard !selectedSection.isLibrary else { return }

        let page: NSView
        switch selectedSection {
        case .displays:
            page = DisplaysPageView(actions: actions, snapshot: snapshot)
        case .automation:
            page = AutomationPageView(actions: actions, snapshot: snapshot)
        case .about:
            page = AboutPageView()
        default:
            return
        }

        pageHost.pin(page)
        currentPage = page
    }

    // MARK: - Inspector and sidebar toggles

    private func setInspector(visible: Bool, remember: Bool = true) {
        if remember { inspectorPreferredVisible = visible }
        guard visible != isInspectorVisible else { return }
        isInspectorVisible = visible
        if visible { inspector.isHidden = false }

        Theme.animate(Theme.panelDuration, changes: {
            self.inspectorWidth.constant = visible ? 300 : 0
            self.inspectorSeparator.alphaValue = visible ? 1 : 0
            self.contentArea.superview?.layoutSubtreeIfNeeded()
        }, completion: {
            self.inspector.isHidden = !visible
            if !visible { self.inspectorView.stopPreview() }
            self.updateGridMetrics()
        })
    }

    private func setSidebar(visible: Bool) {
        guard visible != isSidebarVisible else { return }
        isSidebarVisible = visible
        if visible { sidebar.isHidden = false }
        Theme.animate(Theme.panelDuration, changes: {
            self.sidebarWidth.constant = visible ? 232 : 0
            self.sidebarSeparator.alphaValue = visible ? 1 : 0
            self.contentArea.superview?.layoutSubtreeIfNeeded()
        }, completion: {
            self.sidebar.isHidden = !visible
            self.updateGridMetrics()
        })
    }

    // MARK: - Actions

    @objc private func navRowTapped(_ sender: SidebarRowView) {
        show(section: sender.section)
    }

    @objc private func searchChanged() {
        if !selectedSection.isLibrary {
            show(section: .all)
            return
        }
        model.query.search = searchField.stringValue
    }

    @objc private func toggleSidebar() { setSidebar(visible: !isSidebarVisible) }
    @objc private func toggleInspector() { setInspector(visible: !isInspectorVisible) }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func addWallpaper() { actions.addWallpaper() }
    @objc private func scanFolder() { actions.scanFolder() }
    @objc private func rescan() { model.reload() }

    private func applySelected() {
        guard let pack = selectedPack, pack.unsupportedReason == nil else { return }
        actions.setForThisScreen(pack)
    }

    private func confirmRemove(_ pack: Pack) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(pack.info.title)” from the library?"
        alert.informativeText = "The wallpaper stays on disk. You can restore it from Settings ▸ General."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove from Library")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        actions.removeFromLibrary(pack)
        if selectedPack?.id == pack.id {
            selectedPack = nil
            updateInspector()
        }
        showToast("Removed from Library", actionTitle: "Undo") { [weak self] in
            self?.model.restoreHidden()
        }
    }

    private func duplicate(_ pack: Pack) {
        guard let copy = model.duplicate(pack) else {
            NSSound.beep()
            return
        }
        show(section: .all)
        refresh()
        select(pack: copy)
        showToast("Duplicated “\(pack.info.title)”", actionTitle: nil, action: nil)
    }

    // MARK: - Toast

    private func showToast(_ text: String, actionTitle: String?, action: (() -> Void)?) {
        toastWorkItem?.cancel()
        toast?.removeFromSuperview()

        let toast = ToastView(text: text, actionTitle: actionTitle, action: action)
        toast.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: contentArea.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: hintBar.topAnchor, constant: -14),
        ])
        toast.alphaValue = 0
        self.toast = toast
        Theme.animate(0.2, changes: { toast.alphaValue = 1 })

        let work = DispatchWorkItem { [weak self, weak toast] in
            guard let self, let toast else { return }
            Theme.animate(0.2, changes: { toast.alphaValue = 0 }, completion: {
                toast.removeFromSuperview()
                if self.toast === toast { self.toast = nil }
            })
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        visiblePacks.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: WallpaperCardView.identifier,
            for: indexPath
        )
        guard let card = item as? WallpaperCardView, indexPath.item < visiblePacks.count else {
            return item
        }

        let pack = visiblePacks[indexPath.item]
        card.configure(
            with: pack,
            isFavorite: model.isFavorite(pack),
            isShowing: pack.isShowing(in: snapshot)
        )

        card.onApply = { [weak self] pack in self?.actions.apply(pack) }
        card.onApplyAll = { [weak self] pack in self?.actions.applyToAllScreens(pack) }
        card.onApplyHere = { [weak self] pack in self?.actions.setForThisScreen(pack) }
        card.onReveal = { [weak self] pack in self?.actions.reveal(pack) }
        card.onDuplicate = { [weak self] pack in self?.duplicate(pack) }
        card.onRemove = { [weak self] pack in self?.confirmRemove(pack) }
        card.onToggleFavorite = { [weak self] pack in self?.model.toggleFavorite(pack) }
        return card
    }

    // MARK: - NSCollectionViewDelegate

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !restoringSelection,
              let indexPath = indexPaths.first,
              indexPath.item < visiblePacks.count
        else { return }
        selectedPack = visiblePacks[indexPath.item]
        updateInspector()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !restoringSelection, collectionView.selectionIndexPaths.isEmpty else { return }
        selectedPack = nil
        updateInspector()
    }
}

// MARK: - Gallery collection view

/// Adds the affordances a wallpaper gallery needs: double-click and Return to
/// apply, Space for the live preview.
private final class GalleryCollectionView: NSCollectionView {

    var onActivate: (() -> Void)?
    var onPreview: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onActivate?()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onActivate?()
            return
        case 49:
            onPreview?()
            return
        default:
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Sidebar row

final class SidebarRowView: NSButton {

    let section: LibrarySection

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var isSelectedRow = false
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(section: LibrarySection) {
        self.section = section
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        title = ""
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Theme.Radius.row

        iconView.image = Symbols.image(section.symbol, pointSize: 12, weight: .medium)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = section.title
        titleLabel.font = Theme.body
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = Theme.caption
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -6),

            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setCount(0)
        updateStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func setCount(_ count: Int) {
        countLabel.stringValue = count > 0 ? "\(count)" : ""
    }

    func setSelected(_ selected: Bool) {
        isSelectedRow = selected
        updateStyle()
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
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    private func updateStyle() {
        let background: NSColor
        if isSelectedRow {
            background = Theme.selectionFill
        } else if isHovered {
            background = Theme.rowHover
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor

        let tint: NSColor = isSelectedRow ? Theme.accent : .secondaryLabelColor
        iconView.contentTintColor = tint
        titleLabel.textColor = isSelectedRow ? .labelColor : .labelColor
        titleLabel.font = isSelectedRow ? Theme.font(13, .medium) : Theme.body
        countLabel.textColor = isSelectedRow ? Theme.accent : .tertiaryLabelColor
    }
}

// MARK: - Toast

private final class ToastView: CardView {

    init(text: String, actionTitle: String?, action: (() -> Void)?) {
        super.init(frame: .zero)
        fillColor = Theme.cardFillElevated
        radius = Theme.Radius.control
        castsShadow = true
        shadowStrength = 0.28

        let label = makeLabel(text, font: Theme.callout, color: .labelColor)
        var views: [NSView] = [
            Symbols.view("checkmark.circle.fill", pointSize: 12, weight: .medium, color: Theme.accent),
            label,
        ]

        if let actionTitle, let action {
            let button = HoverButton(actionTitle, style: .borderless, target: nil, action: nil)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let target = ActionTarget { _ in action() }
            button.target = target
            button.action = #selector(ActionTarget.fire(_:))
            actionTarget = target
            views.append(button)
        }

        let row = hstack(views, spacing: 8)
        pin(row, insets: NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 10))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private var actionTarget: ActionTarget?
}


/// The library window handles the app's navigation shortcuts itself. Tangent
/// lives in the menu bar and has no main menu, so key equivalents would
/// otherwise never reach the window.
private final class LibraryWindow: NSWindow {

    weak var controller: LibraryWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if controller?.performShortcut(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

extension LibraryWindowController {

    /// ⌘1 library, ⌘2 displays, ⌘, settings and ⌘W close, regardless of which
    /// control currently holds focus.
    fileprivate func performShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == .command, let key = event.charactersIgnoringModifiers else { return false }

        switch key {
        case "1":
            show(section: .all)
            return true
        case "2":
            show(section: .displays)
            return true
        case ",":
            actions.openSettings()
            return true
        case "w":
            window?.performClose(nil)
            return true
        default:
            return false
        }
    }
}
