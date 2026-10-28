import AppKit

/// Library browser: a searchable, filterable gallery of wallpaper packs with a
/// details bar. Selecting a tile only inspects it; applying happens on double
/// click, Return, or the Apply button, so browsing cannot replace the desktop by
/// accident.
final class LibraryWindowController: NSWindowController,
    NSCollectionViewDataSource, NSCollectionViewDelegate {

    private let model: LibraryModel
    private let onAdd: () -> Void
    private let onScanFolder: () -> Void

    private var collectionView: LibraryCollectionView!
    private var searchField: NSSearchField!
    private var filterPopup: NSPopUpButton!
    private var countLabel: NSTextField!
    private var emptyLabel: NSTextField!

    private var detailTitle: NSTextField!
    private var detailSubtitle: NSTextField!
    private var detailPath: NSTextField!
    private var applyButton: NSButton!
    private var revealButton: NSButton!

    private var selectedPack: Pack?

    private var visiblePacks: [Pack] { model.visiblePacks }

    init(model: LibraryModel, onAdd: @escaping () -> Void, onScanFolder: @escaping () -> Void) {
        self.model = model
        self.onAdd = onAdd
        self.onScanFolder = onScanFolder

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tangent Library"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 520)

        super.init(window: window)

        buildInterface()
        model.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func present() {
        model.reload()
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
        guard let selection else { return }
        let packs = visiblePacks
        guard packs.indices.contains(selection) else { return }
        let indexPath = IndexPath(item: selection, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        selectedPack = packs[selection]
        updateDetails()
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        // Toolbar: library actions, then search/filter so the grid stays the
        // visual focus.
        let addButton = NSButton(title: "Add Wallpaper…", target: self, action: #selector(addTapped))
        let scanButton = NSButton(title: "Scan Folder…", target: self, action: #selector(scanTapped))
        let rescanButton = NSButton(title: "Rescan", target: self, action: #selector(rescanTapped))

        searchField = NSSearchField()
        searchField.placeholderString = "Search wallpapers"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        filterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        filterPopup.addItems(withTitles: LibraryFilter.allCases.map(\.title))
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged)
        filterPopup.translatesAutoresizingMaskIntoConstraints = false
        filterPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        countLabel = NSTextField(labelWithString: "")
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.alignment = .right

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolbar = NSStackView(views: [
            addButton, scanButton, rescanButton, spacer,
            searchField, filterPopup, countLabel,
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 226, height: 232)
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 14

        collectionView = LibraryCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            LibraryItemView.self,
            forItemWithIdentifier: LibraryItemView.identifier
        )
        collectionView.onActivate = { [weak self] in self?.applySelected() }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel = NSTextField(labelWithString: "")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.maximumNumberOfLines = 4
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let toolbarDivider = NSBox()
        toolbarDivider.boxType = .separator
        toolbarDivider.translatesAutoresizingMaskIntoConstraints = false

        // Details bar: inspecting a wallpaper is free; Apply is explicit.
        detailTitle = NSTextField(labelWithString: "Select a wallpaper")
        detailTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        detailTitle.lineBreakMode = .byTruncatingTail

        detailSubtitle = NSTextField(labelWithString: "Double-click a tile, or press Return, to apply it.")
        detailSubtitle.font = .systemFont(ofSize: 11)
        detailSubtitle.textColor = .secondaryLabelColor
        detailSubtitle.lineBreakMode = .byTruncatingTail

        detailPath = NSTextField(labelWithString: "")
        detailPath.font = .systemFont(ofSize: 10)
        detailPath.textColor = .tertiaryLabelColor
        detailPath.lineBreakMode = .byTruncatingMiddle
        detailPath.isSelectable = true

        let detailText = NSStackView(views: [detailTitle, detailSubtitle, detailPath])
        detailText.orientation = .vertical
        detailText.alignment = .leading
        detailText.spacing = 2

        let detailSpacer = NSView()
        detailSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        revealButton = NSButton(title: "Reveal", target: self, action: #selector(revealTapped))
        revealButton.bezelStyle = .inline
        revealButton.isEnabled = false

        applyButton = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.isEnabled = false

        let details = NSStackView(views: [
            detailText, detailSpacer, revealButton, applyButton,
        ])
        details.orientation = .horizontal
        details.alignment = .centerY
        details.spacing = 10
        details.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        details.translatesAutoresizingMaskIntoConstraints = false

        let detailsDivider = NSBox()
        detailsDivider.boxType = .separator
        detailsDivider.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(toolbar)
        content.addSubview(toolbarDivider)
        content.addSubview(scrollView)
        content.addSubview(emptyLabel)
        content.addSubview(detailsDivider)
        content.addSubview(details)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            toolbarDivider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            toolbarDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbarDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: toolbarDivider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: detailsDivider.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),

            detailsDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            detailsDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailsDivider.bottomAnchor.constraint(equalTo: details.topAnchor),

            details.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            details.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            details.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
        ])
    }

    // MARK: - State

    private func refresh() {
        let packs = visiblePacks
        collectionView?.reloadData()

        let total = model.packs.count
        if packs.count == total {
            countLabel?.stringValue = "\(total) item\(total == 1 ? "" : "s")"
        } else {
            countLabel?.stringValue = "\(packs.count) of \(total)"
        }

        if model.packs.isEmpty {
            emptyLabel?.stringValue = "No wallpapers yet.\nAdd a wallpaper pack folder, or scan a folder full of them."
        } else {
            emptyLabel?.stringValue = "No wallpapers match your search or filter."
        }
        emptyLabel?.isHidden = !packs.isEmpty

        restoreSelection(in: packs)
    }

    /// Keeps the same wallpaper selected across a search, filter or rescan when
    /// it is still visible.
    private func restoreSelection(in packs: [Pack]) {
        guard let identifier = selectedPack?.id,
              let index = packs.firstIndex(where: { $0.id == identifier })
        else {
            selectedPack = nil
            collectionView?.deselectAll(nil)
            updateDetails()
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        collectionView?.selectItems(at: [indexPath], scrollPosition: [])
        selectedPack = packs[index]
        updateDetails()
    }

    private func updateDetails() {
        guard let pack = selectedPack else {
            detailTitle.stringValue = "Select a wallpaper"
            detailSubtitle.stringValue = "Double-click a tile, or press Return, to apply it."
            detailPath.stringValue = ""
            applyButton.isEnabled = false
            revealButton.isEnabled = false
            return
        }

        detailTitle.stringValue = pack.info.title

        var parts = [pack.info.type.displayName]
        if let author = pack.info.author, !author.isEmpty {
            parts.append(author)
        }
        if let reason = pack.unsupportedReason {
            parts.append(reason)
            detailSubtitle.textColor = .systemOrange
        } else {
            detailSubtitle.textColor = .secondaryLabelColor
        }
        detailSubtitle.stringValue = parts.joined(separator: " · ")

        detailPath.stringValue = pack.libraryEntry.path
        detailPath.toolTip = pack.libraryEntry.path

        applyButton.isEnabled = pack.unsupportedReason == nil
        applyButton.toolTip = pack.unsupportedReason
        revealButton.isEnabled = true
    }

    private func applySelected() {
        guard let pack = selectedPack, pack.unsupportedReason == nil else { return }
        model.onApply?(pack)
    }

    // MARK: - Actions

    @objc private func addTapped() { onAdd() }
    @objc private func scanTapped() { onScanFolder() }
    @objc private func rescanTapped() { model.reload() }

    @objc private func searchChanged() {
        model.query.search = searchField.stringValue
    }

    @objc private func filterChanged() {
        let index = filterPopup.indexOfSelectedItem
        guard LibraryFilter.allCases.indices.contains(index) else { return }
        model.query.filter = LibraryFilter.allCases[index]
    }

    @objc private func applyTapped() { applySelected() }

    @objc private func revealTapped() {
        guard let pack = selectedPack else { return }
        NSWorkspace.shared.activateFileViewerSelecting([pack.libraryEntry])
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
            withIdentifier: LibraryItemView.identifier,
            for: indexPath
        )
        if let cell = item as? LibraryItemView, indexPath.item < visiblePacks.count {
            cell.configure(with: visiblePacks[indexPath.item])
        }
        return item
    }

    // MARK: - NSCollectionViewDelegate

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, indexPath.item < visiblePacks.count else { return }
        selectedPack = visiblePacks[indexPath.item]
        updateDetails()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        if collectionView.selectionIndexPaths.isEmpty {
            selectedPack = nil
            updateDetails()
        }
    }
}

// MARK: - Collection view

/// Adds the two affordances a gallery needs but `NSCollectionView` does not
/// provide directly: double-click and Return to activate the selection.
private final class LibraryCollectionView: NSCollectionView {
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onActivate?()
        }
    }

    override func keyDown(with event: NSEvent) {
        // Return and keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onActivate?()
            return
        }
        super.keyDown(with: event)
    }
}
