import AppKit

/// One wallpaper tile: thumbnail, title, author, type badge, and the reason it
/// cannot run when the type is unsupported.
final class LibraryItemView: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("LibraryItemView")

    private let thumbView = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")
    private let reasonLabel = NSTextField(wrappingLabelWithString: "")

    private var currentID: String?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        root.layer?.cornerRadius = 10
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.separatorColor.cgColor

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 8
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.backgroundColor = NSColor.black.cgColor

        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        badge.layer?.cornerRadius = 6
        badge.alignment = .center
        badge.drawsBackground = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        authorLabel.font = .systemFont(ofSize: 11)
        authorLabel.textColor = .secondaryLabelColor
        authorLabel.lineBreakMode = .byTruncatingTail
        authorLabel.maximumNumberOfLines = 1

        reasonLabel.font = .systemFont(ofSize: 10)
        reasonLabel.textColor = .systemOrange
        reasonLabel.maximumNumberOfLines = 3

        for view in [thumbView, badge, titleLabel, authorLabel, reasonLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            thumbView.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            thumbView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            thumbView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            thumbView.heightAnchor.constraint(equalToConstant: 118),

            badge.topAnchor.constraint(equalTo: thumbView.topAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -6),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            badge.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            authorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            authorLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            reasonLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 4),
            reasonLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            reasonLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            reasonLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -8),
        ])

        view = root
    }

    func configure(with pack: Pack) {
        currentID = pack.id

        titleLabel.stringValue = pack.info.title
        badge.stringValue = " " + pack.info.type.displayName + " "

        if let author = pack.info.author, !author.isEmpty {
            authorLabel.stringValue = author
            authorLabel.isHidden = false
        } else {
            authorLabel.stringValue = ""
            authorLabel.isHidden = true
        }

        if let reason = pack.unsupportedReason {
            reasonLabel.stringValue = reason
            reasonLabel.isHidden = false
            view.alphaValue = 0.55
        } else {
            reasonLabel.stringValue = ""
            reasonLabel.isHidden = true
            view.alphaValue = 1
        }

        view.toolTip = pack.unsupportedReason ?? pack.info.summary

        thumbView.image = nil
        Task { [weak self] in
            let image = await ThumbnailProvider.shared.thumbnail(for: pack)
            await MainActor.run {
                guard let self, self.currentID == pack.id else { return }
                self.thumbView.image = image
            }
        }
    }
}
