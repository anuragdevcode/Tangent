import AppKit

/// Standalone About window. Settings and the Library also show the same content,
/// but a dedicated window is what people expect from “About Tangent”.
final class AboutWindowController: NSWindowController {

    private let aboutPage: AboutFeedbackPage

    init(actions: AppActions) {
        aboutPage = AboutFeedbackPage(centered: true, actions: actions)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About Tangent"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        super.init(window: window)

        let background = VisualEffectView(material: .hudWindow, blending: .behindWindow)
        background.translatesAutoresizingMaskIntoConstraints = false

        let content = aboutPage
        let scroll = makePageScroll(content: content, maxWidth: 400)
        scroll.drawsBackground = false

        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: 26),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
        ])

        window.contentView = background
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    func present() {
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Redraws the live update card without rebuilding the window.
    func reload() {
        aboutPage.reload()
    }
}
