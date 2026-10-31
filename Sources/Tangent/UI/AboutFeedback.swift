import AppKit

// MARK: - Page

/// About & Feedback: application identity, update state, help routes and the
/// community links. Shared by Settings, the standalone About window and the
/// library's About page so all three stay identical.
final class AboutFeedbackPage: NSView {

    private let actions: AppActions
    private let updatesCard: UpdatesCardView

    init(centered: Bool, actions: AppActions) {
        self.actions = actions
        self.updatesCard = UpdatesCardView(actions: actions)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let helpCard = HelpSupportCardView(actions: actions)
        let communityCard = CommunityCardView(actions: actions)

        var views: [NSView] = []
        if centered {
            views.append(centeredRow([AboutContent.mark(size: 84)]))
            views.append(AboutContent.titleBlock(centered: true))
        } else {
            views.append(
                hstack(
                    [AboutContent.mark(size: 64), AboutContent.titleBlock(centered: false)],
                    spacing: 16
                )
            )
        }
        views.append(contentsOf: [
            AboutContent.blurb(centered: centered),
            AboutContent.primaryActions(),
            spacing(4),
            updatesCard,
            helpCard,
            communityCard,
            AboutContent.supportCard(),
            spacing(4),
            AboutContent.details(),
            spacing(8),
            AboutContent.licenseLine(centered: centered),
        ])

        let stack = vstack(
            views,
            spacing: Theme.Spacing.medium,
            alignment: centered ? .centerX : .leading
        )
        if centered {
            stack.setCustomSpacing(18, after: views[0])
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Cards run the full column width; the smaller controls keep their
        // intrinsic size.
        for card in [updatesCard, helpCard, communityCard] {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        apply(snapshot: actions.snapshot())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    /// Refreshes the live update section without rebuilding the page.
    func apply(snapshot: AppSnapshot) {
        updatesCard.apply(snapshot: snapshot)
    }

    /// Re-reads the app snapshot and updates the live card in place.
    func reload() {
        apply(snapshot: actions.snapshot())
    }
}

// MARK: - Updates card

final class UpdatesCardView: CardView {

    private let actions: AppActions
    private var targets: [ActionTarget] = []

    private let statusPill = StatusPillView(text: "Not Checked")
    private let detailLabel = makeWrappingLabel("", font: Theme.caption)
    private let checkButton = HoverButton(
        "Check for Updates",
        symbol: "arrow.triangle.2.circlepath",
        style: .filled
    )
    private let downloadButton = HoverButton(
        "Download Update",
        symbol: "arrow.down.circle",
        style: .accent
    )
    private let notesButton = HoverButton("Release Notes", symbol: "doc.text", style: .borderless)
    private let spinner = NSProgressIndicator()

    init(actions: AppActions) {
        self.actions = actions
        super.init(frame: .zero)

        radius = Theme.Radius.card
        fillColor = Theme.cardFill
        statusPill.setAccessibilityLabel("Update status")

        wire(checkButton) { actions.checkForUpdates() }
        wire(downloadButton) { actions.downloadUpdate() }
        wire(notesButton) { actions.openReleaseNotes() }

        for button in [checkButton, downloadButton, notesButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        notesButton.font = Theme.caption

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.isHidden = true

        let header = cardHeader(
            symbol: "arrow.triangle.2.circlepath",
            tint: Theme.accent,
            title: "Updates",
            trailing: statusPill
        )
        let buttons = hstack(
            [checkButton, spinner, downloadButton, notesButton, flexibleSpacer()],
            spacing: 8
        )
        let stack = vstack([header, detailLabel, buttons], spacing: 10)
        pin(stack, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        downloadButton.isHidden = true
        notesButton.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func apply(snapshot: AppSnapshot) {
        let state = snapshot.updateState
        let installed = "Installed \(Format.version())"
        let checked = lastCheckedText(snapshot.lastUpdateCheck)

        spinner.stopAnimation(nil)
        spinner.isHidden = true
        checkButton.isHidden = false
        checkButton.isEnabled = true
        checkButton.title = "Check for Updates"
        downloadButton.isHidden = true
        notesButton.isHidden = true

        switch state {
        case .idle:
            statusPill.configure(text: "Not Checked", tint: .secondaryLabelColor)
            detailLabel.stringValue = "\(installed) · \(checked)"
        case .checking:
            statusPill.configure(text: "Checking…", tint: Theme.accent)
            detailLabel.stringValue = "\(installed) · Contacting GitHub…"
            spinner.isHidden = false
            spinner.startAnimation(nil)
            checkButton.title = "Checking for Updates…"
            checkButton.isEnabled = false
        case .upToDate:
            statusPill.configure(text: "Up to Date", tint: Theme.positive)
            detailLabel.stringValue = "\(installed) · You’re running the latest release · \(checked)"
        case .updateAvailable(let update):
            statusPill.configure(text: "Update Available", tint: Theme.accent)
            detailLabel.stringValue = "\(installed) · Latest \(update.version) available · \(checked)"
            downloadButton.isHidden = false
            downloadButton.title = update.isDirectDownload ? "Download Update" : "View Release"
            notesButton.isHidden = update.releasePageURL == nil
        case .offline:
            statusPill.configure(text: "Offline", tint: Theme.warning)
            detailLabel.stringValue = "\(installed) · Couldn’t reach GitHub. Check your connection. · \(checked)"
        case .rateLimited:
            statusPill.configure(text: "Rate Limited", tint: Theme.warning)
            detailLabel.stringValue = "\(installed) · GitHub’s rate limit was reached. Try again later."
        case .failed(let message):
            statusPill.configure(text: "Check Failed", tint: Theme.warning)
            detailLabel.stringValue = "\(installed) · \(message)"
        }

        checkButton.applyStyle()
        downloadButton.applyStyle()
        notesButton.applyStyle()
    }

    // MARK: Helpers

    private func lastCheckedText(_ date: Date?) -> String {
        guard let date else { return "Never checked" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Last checked \(formatter.string(from: date))"
    }

    private func wire(_ button: HoverButton, _ handler: @escaping () -> Void) {
        let target = ActionTarget { _ in handler() }
        targets.append(target)
        button.target = target
        button.action = #selector(ActionTarget.fire(_:))
    }
}

// MARK: - Help & Support card

final class HelpSupportCardView: CardView {

    private var targets: [ActionTarget] = []

    init(actions: AppActions) {
        super.init(frame: .zero)

        radius = Theme.Radius.card
        fillColor = Theme.cardFill

        let report = HoverButton("Report a Bug", symbol: "ladybug.fill", style: .filled)
        let feedback = HoverButton(
            "Share Feedback",
            symbol: "bubble.left.and.bubble.right.fill",
            style: .outlined
        )
        let copy = HoverButton("Copy Diagnostics", symbol: "doc.on.doc", style: .borderless)
        copy.font = Theme.caption

        wire(report) { actions.reportBug() }
        wire(feedback) { actions.shareFeedback() }
        wire(copy) { actions.copyDiagnostics() }

        for button in [report, feedback] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let note = makeWrappingLabel(
            "A short technical summary is copied to your clipboard for review. "
                + "Nothing is sent automatically.",
            font: Theme.caption,
            color: .secondaryLabelColor
        )

        let header = cardHeader(
            symbol: "ladybug.fill",
            tint: Theme.warning,
            title: "Help & Support"
        )
        let buttons = hstack([report, feedback, copy, flexibleSpacer()], spacing: 8)
        let stack = vstack([header, note, buttons], spacing: 9)
        pin(stack, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private func wire(_ button: HoverButton, _ handler: @escaping () -> Void) {
        let target = ActionTarget { _ in handler() }
        targets.append(target)
        button.target = target
        button.action = #selector(ActionTarget.fire(_:))
    }
}

// MARK: - Community card

final class CommunityCardView: CardView {

    private var targets: [ActionTarget] = []

    init(actions: AppActions) {
        super.init(frame: .zero)

        radius = Theme.Radius.card
        fillColor = Theme.cardFill

        let discussions = HoverButton(
            "Discussions",
            symbol: "bubble.left.and.bubble.right",
            style: .outlined
        )
        let star = HoverButton("Star Tangent", symbol: "star.fill", style: .outlined)
        let repository = HoverButton(
            "GitHub Repository",
            symbol: "chevron.left.forwardslash.chevron.right",
            style: .outlined
        )
        let releases = HoverButton("Release Notes", symbol: "tag", style: .outlined)

        wire(discussions) { actions.shareFeedback() }
        wire(star) { actions.openRepository() }
        wire(repository) { actions.openRepository() }
        wire(releases) { actions.openReleaseNotes() }

        for button in [discussions, star, repository, releases] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }

        let note = makeWrappingLabel(
            "Share wallpapers, suggest features, or follow development on GitHub.",
            font: Theme.caption,
            color: .secondaryLabelColor
        )

        let header = cardHeader(
            symbol: "person.3.fill",
            tint: .systemPurple,
            title: "Community"
        )
        let topRow = hstack([discussions, star, flexibleSpacer()], spacing: 8)
        let bottomRow = hstack([repository, releases, flexibleSpacer()], spacing: 8)
        let stack = vstack([header, note, topRow, bottomRow], spacing: 9)
        pin(stack, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        topRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bottomRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private func wire(_ button: HoverButton, _ handler: @escaping () -> Void) {
        let target = ActionTarget { _ in handler() }
        targets.append(target)
        button.target = target
        button.action = #selector(ActionTarget.fire(_:))
    }
}

// MARK: - Shared pieces

/// Rounded, tinted glyph tile used at the leading edge of each card.
func cardIconTile(_ symbol: String, tint: NSColor) -> NSView {
    let tile = CardView()
    tile.radius = 10
    tile.fillColor = tint.withAlphaComponent(0.14)
    tile.borderColor = nil
    tile.translatesAutoresizingMaskIntoConstraints = false

    let icon = Symbols.view(symbol, pointSize: 17, weight: .semibold, color: tint)
    tile.addSubview(icon)
    NSLayoutConstraint.activate([
        tile.widthAnchor.constraint(equalToConstant: 38),
        tile.heightAnchor.constraint(equalToConstant: 38),
        icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
    ])
    return tile
}

/// Icon + title, with an optional trailing status view.
func cardHeader(
    symbol: String,
    tint: NSColor,
    title: String,
    trailing: NSView? = nil
) -> NSView {
    let titleLabel = makeLabel(title, font: Theme.font(14, .semibold))
    var items: [NSView] = [cardIconTile(symbol, tint: tint), titleLabel]
    if let trailing {
        items.append(inflexibleSpacer())
        items.append(trailing)
    }
    let row = hstack(items, spacing: 10)
    row.setCustomSpacing(12, after: items[0])
    return row
}

// MARK: - Bug report flow

/// A short privacy preview before GitHub opens. Diagnostics stay local until
/// the user pastes them into the issue form.
enum BugReportFlow {

    static func present(manager: FeedbackManager, from window: NSWindow?) {
        let diagnostics = manager.collectDiagnostics()
        let report = manager.diagnosticText(diagnostics)
        let url = manager.bugReportURL(title: manager.issueTitle(diagnostics))

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Report a Bug"
        alert.informativeText = """
        Review the summary below, then continue to GitHub. Issue forms can’t be \
        filled in from a link, so the summary is copied to your clipboard for the \
        Diagnostics field. Nothing is submitted until you finish the form.
        """

        let scroll = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 440, height: 168)
        )
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.setAccessibilityLabel("Diagnostic summary")

        let textView = NSTextView(frame: scroll.bounds)
        textView.string = report
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 440,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("Diagnostic summary")
        scroll.documentView = textView
        alert.accessoryView = scroll

        alert.addButton(withTitle: "Copy & Open GitHub")
        alert.addButton(withTitle: "Copy Only")
        alert.addButton(withTitle: "Cancel")

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn:
                _ = manager.copyDiagnostics(diagnostics)
                ExternalLink.open(url)
            case .alertSecondButtonReturn:
                _ = manager.copyDiagnostics(diagnostics)
            default:
                break
            }
        }

        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}
