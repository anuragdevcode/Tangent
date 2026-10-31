import AppKit
import AVFoundation

/// One wallpaper in the gallery.
///
/// A 16:10 preview over a title block, with a hover lift, an inline muted video
/// preview for AVFoundation-backed packs, a favorite control and an accent ring
/// when the wallpaper is on the desktop.
final class WallpaperCardView: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("WallpaperCardView")

    private let container = CardView()
    private let preview = CardPreviewView()
    private let titleLabel = makeLabel("", font: Theme.cardTitle)
    private let subtitleLabel = makeLabel("", font: Theme.caption, color: .secondaryLabelColor)
    private let typeBadge = BadgeView()
    private let activeBadge = BadgeView()
    private let favoriteButton = IconButton(
        symbol: "star",
        pointSize: 11,
        style: .quiet,
        toolTip: "Favorite"
    )
    private let unsupportedLabel = makeLabel("", font: Theme.tiny, color: .systemOrange)

    private var pack: Pack?
    private var isFavorite = false
    private var isShowingNow = false
    private var isHovering = false

    // Context menu callbacks.
    var onApply: ((Pack) -> Void)?
    var onApplyAll: ((Pack) -> Void)?
    var onApplyHere: ((Pack) -> Void)?
    var onReveal: ((Pack) -> Void)?
    var onDuplicate: ((Pack) -> Void)?
    var onRemove: ((Pack) -> Void)?
    var onToggleFavorite: ((Pack) -> Void)?

    override func loadView() {
        let root = CardRootView(frame: NSRect(x: 0, y: 0, width: 240, height: 215))
        root.wantsLayer = true
        root.onHover = { [weak self] hovering in self?.setHovering(hovering) }
        view = root

        container.radius = Theme.Radius.card
        container.fillColor = Theme.cardFill
        container.castsShadow = true
        container.shadowStrength = 0
        container.shadowRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 5),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -5),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5),
        ])

        preview.radius = Theme.Radius.preview
        preview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(preview)

        typeBadge.translatesAutoresizingMaskIntoConstraints = false
        activeBadge.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        unsupportedLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(typeBadge)
        container.addSubview(activeBadge)
        container.addSubview(favoriteButton)

        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteTapped)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(unsupportedLabel)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 10.0 / 16.0),

            typeBadge.topAnchor.constraint(equalTo: preview.topAnchor, constant: 7),
            typeBadge.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 7),

            favoriteButton.topAnchor.constraint(equalTo: preview.topAnchor, constant: 5),
            favoriteButton.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -5),

            activeBadge.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -7),
            activeBadge.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -7),

            titleLabel.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -11),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            unsupportedLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 2),
            unsupportedLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            unsupportedLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            unsupportedLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Content

    func configure(
        with pack: Pack,
        isFavorite: Bool,
        isShowing: Bool
    ) {
        self.pack = pack
        self.isFavorite = isFavorite
        self.isShowingNow = isShowing

        titleLabel.stringValue = pack.info.title

        if let author = pack.info.author, !author.isEmpty {
            subtitleLabel.stringValue = author
            subtitleLabel.textColor = .secondaryLabelColor
        } else {
            subtitleLabel.stringValue = pack.info.type.displayName
            subtitleLabel.textColor = .secondaryLabelColor
        }

        typeBadge.configure(
            text: pack.info.type.displayName.uppercased(),
            symbol: pack.info.type.glyph,
            tint: .white,
            background: NSColor.black.withAlphaComponent(0.55)
        )

        favoriteButton.image = Symbols.image(
            isFavorite ? "star.fill" : "star",
            pointSize: 11,
            weight: .medium
        )
        favoriteButton.contentTintColor = isFavorite ? .systemYellow : .white
        favoriteButton.toolTip = isFavorite ? "Remove from Favorites" : "Add to Favorites"

        activeBadge.isHidden = !isShowing
        if isShowing {
            activeBadge.configure(
                text: "Current Desktop",
                symbol: "checkmark",
                tint: .white,
                background: Theme.accent
            )
        }

        if let reason = pack.unsupportedReason {
            unsupportedLabel.stringValue = reason
            unsupportedLabel.isHidden = false
            subtitleLabel.isHidden = true
        } else {
            unsupportedLabel.isHidden = true
            subtitleLabel.isHidden = false
        }

        preview.set(pack: pack, dimmed: pack.unsupportedReason != nil)
        view.toolTip = pack.unsupportedReason ?? pack.info.summary
        view.menu = buildMenu()
        updateSelectionAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        preview.stop()
        isHovering = false
        container.layer?.transform = CATransform3DIdentity
        container.shadowStrength = 0
        pack = nil
    }

    // MARK: - Selection and highlight

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        let selected = isSelected
        container.borderWidth = selected || isShowingNow ? 2 : 1
        container.borderColor = selected || isShowingNow ? Theme.accent : Theme.hairline
        container.fillColor = selected ? Theme.cardFillElevated : Theme.cardFill
    }

    // MARK: - Hover

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering

        let scale: CGFloat = hovering ? 1.02 : 1
        let transform = CATransform3DMakeScale(scale, scale, 1)
        let current = container.layer?.presentation()?.transform ?? container.layer?.transform ?? CATransform3DIdentity
        let animation = Theme.springAnimation(
            keyPath: "transform",
            from: NSValue(caTransform3D: current),
            to: NSValue(caTransform3D: transform)
        )
        container.layer?.transform = transform
        container.layer?.add(animation, forKey: "hover-lift")

        container.shadowStrength = hovering ? 0.38 : 0
        if hovering {
            preview.beginHover()
        } else {
            preview.endHover()
        }
    }

    // MARK: - Actions

    @objc private func favoriteTapped() {
        guard let pack else { return }
        onToggleFavorite?(pack)
    }

    @objc private func menuApply() {
        guard let pack else { return }
        onApply?(pack)
    }

    @objc private func menuApplyAll() {
        guard let pack else { return }
        onApplyAll?(pack)
    }

    @objc private func menuApplyHere() {
        guard let pack else { return }
        onApplyHere?(pack)
    }

    @objc private func menuReveal() {
        guard let pack else { return }
        onReveal?(pack)
    }

    @objc private func menuDuplicate() {
        guard let pack else { return }
        onDuplicate?(pack)
    }

    @objc private func menuRemove() {
        guard let pack else { return }
        onRemove?(pack)
    }

    @objc private func menuFavorite() {
        guard let pack else { return }
        onToggleFavorite?(pack)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let playable = pack?.unsupportedReason == nil

        let apply = menu.addItem(
            withTitle: isShowingNow ? "Apply Again" : "Set for This Screen",
            action: #selector(menuApplyHere),
            keyEquivalent: ""
        )
        apply.target = self
        apply.isEnabled = playable

        let all = menu.addItem(
            withTitle: "Set for All Screens",
            action: #selector(menuApplyAll),
            keyEquivalent: ""
        )
        all.target = self
        all.isEnabled = playable

        if !isShowingNow, playable {
            let applyDefault = menu.addItem(
                withTitle: "Make Default Wallpaper",
                action: #selector(menuApply),
                keyEquivalent: ""
            )
            applyDefault.target = self
        }

        menu.addItem(.separator())

        let favorite = menu.addItem(
            withTitle: isFavorite ? "Remove from Favorites" : "Add to Favorites",
            action: #selector(menuFavorite),
            keyEquivalent: ""
        )
        favorite.target = self

        let duplicate = menu.addItem(
            withTitle: "Duplicate",
            action: #selector(menuDuplicate),
            keyEquivalent: ""
        )
        duplicate.target = self

        let reveal = menu.addItem(
            withTitle: "Show in Finder",
            action: #selector(menuReveal),
            keyEquivalent: ""
        )
        reveal.target = self

        menu.addItem(.separator())

        let remove = menu.addItem(
            withTitle: "Remove from Library…",
            action: #selector(menuRemove),
            keyEquivalent: ""
        )
        remove.target = self
        return menu
    }
}

// MARK: - Preview surface

/// Clipped preview with an optional muted, looping video on hover.
private final class CardPreviewView: NSView {

    private let imageView = NSImageView()
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var previewURL: URL?
    private var currentID: String?
    private var hoverWorkItem: DispatchWorkItem?
    private var isHovering = false

    var radius: CGFloat = Theme.Radius.preview {
        didSet { layer?.cornerRadius = radius }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.previewPlaceholder.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.previewPlaceholder.cgColor
    }

    func set(pack: Pack, dimmed: Bool) {
        let identifier = pack.id
        currentID = identifier
        alphaValue = dimmed ? 0.55 : 1
        imageView.image = nil
        previewURL = nil
        stop()

        if pack.info.type == .video,
           let url = pack.entryURL,
           VideoRouting.backend(for: url) == .avFoundation {
            previewURL = url
        }

        Task { [weak self] in
            let image = await ThumbnailProvider.shared.thumbnail(for: pack)
            await MainActor.run {
                guard let self, self.currentID == identifier else { return }
                self.imageView.image = image
            }
        }
    }

    func beginHover() {
        isHovering = true
        guard let previewURL else { return }
        hoverWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHovering else { return }
            self.startPlayer(url: previewURL)
        }
        hoverWorkItem = work
        // A short delay keeps fast scrubbing over the grid from spawning a
        // decoder per card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func endHover() {
        isHovering = false
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        stop()
    }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        playerLayer.isHidden = true
        // The still is the fallback, so it comes back with the layer.
        imageView.isHidden = false
        player = nil
        looper = nil
    }

    private func startPlayer(url: URL) {
        guard player == nil else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        playerLayer.player = queue
        // `playerLayer` is a sublayer, and AppKit keeps subview layers above
        // sibling sublayers. Hiding the still makes the video the only thing
        // the card draws while it plays.
        imageView.isHidden = true
        playerLayer.isHidden = false
        queue.play()
        player = queue
        looper = loop
    }
}

// MARK: - Root view

/// Tracks the pointer for the whole card. Tracking belongs on the view rather
/// than the item controller so the hover state is reliable inside a collection
/// view.
private final class CardRootView: NSView {

    var onHover: ((Bool) -> Void)?
    private var trackingAreaReference: NSTrackingArea?

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
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

// MARK: - Type glyphs

extension WallpaperType {
    var glyph: String {
        switch self {
        case .video: return "film"
        case .web, .webaudio, .url: return "globe"
        case .gif, .picture: return "photo"
        default: return "exclamationmark.triangle"
        }
    }
}
