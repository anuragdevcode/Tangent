import AppKit
import WebKit

/// Ko-fi integration.
///
/// Ko-fi's share page offers JavaScript buttons, but those only open the tip
/// page in a browser tab, and their iframe embed renders nothing outside
/// ko-fi.com. Tangent keeps the tip flow in the app instead: the About surfaces
/// use a Ko-fi-branded button, and both it and the popover's heart open the real
/// Ko-fi page inside a native window.
enum KoFi {
    static let pageURL = TangentLinks.support
}

// MARK: - Button

/// The support button on the About surfaces. It is deliberately native: a web
/// widget here would load Ko-fi's scripts just to draw a 174 pt pill and could
/// not be captured by the in-process snapshot checks.
final class KoFiSupportButton: HoverButton {

    init() {
        super.init(
            "Support me on Ko-fi",
            symbol: "cup.and.saucer.fill",
            style: .koFi,
            target: nil,
            action: nil
        )
        target = self
        action = #selector(open)
        toolTip = "Tip Anurag through Ko-fi without leaving Tangent"
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    @objc private func open() {
        KoFiSupportWindowController.shared.present()
    }
}

// MARK: - Support window

/// The Ko-fi page hosted inside Tangent, with a browser escape hatch and a
/// retry path for offline machines.
final class KoFiSupportWindowController: NSWindowController,
    NSWindowDelegate, WKNavigationDelegate, WKUIDelegate
{
    static let shared = KoFiSupportWindowController()

    /// A throwaway session for `--probe-kofi`, so the check sees exactly what a
    /// first-time visitor sees rather than the developer's own logged-in page.
    static func makeForProbe() -> KoFiSupportWindowController {
        KoFiSupportWindowController(dataStore: .nonPersistent())
    }

    /// Exposed read-only so `--probe-kofi` inspects the real window instead of
    /// building a second copy of it.
    private(set) var webView: WKWebView

    /// Probe hooks; the support window itself never sets them.
    var onLoad: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    private let spinner = NSProgressIndicator()
    private let errorView = NSView()
    private let errorLabel = makeWrappingLabel(
        "Couldn’t reach Ko-fi. Check your connection and try again.",
        font: Theme.caption,
        color: .secondaryLabelColor
    )

    private var hasLoaded = false
    private var hasPositioned = false

    private init(dataStore: WKWebsiteDataStore = .default()) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "Support Tangent"
        window.minSize = NSSize(width: 400, height: 560)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        build(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    // MARK: Layout

    private func build(in window: NSWindow) {
        let root = CanvasView()
        window.contentView = root

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = false
        webView.setAccessibilityLabel("Ko-fi support page")
        root.addSubview(webView)

        let footer = PaneView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)

        let separator = HairlineView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(separator)

        let hint = makeLabel(
            "Tips are processed by Ko-fi.",
            font: Theme.tiny,
            color: .tertiaryLabelColor
        )
        let browser = HoverButton(
            "Open in Browser",
            symbol: "safari",
            style: .borderless,
            target: self,
            action: #selector(openInBrowser)
        )
        browser.font = Theme.caption
        browser.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let footerRow = hstack([hint, flexibleSpacer(), browser], spacing: 8)
        footer.addSubview(footerRow)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isDisplayedWhenStopped = false
        root.addSubview(spinner)

        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        root.addSubview(errorView)

        let errorIcon = Symbols.view(
            "wifi.exclamationmark",
            pointSize: 24,
            color: .secondaryLabelColor
        )
        let retry = HoverButton(
            "Try Again",
            symbol: "arrow.clockwise",
            style: .filled,
            target: self,
            action: #selector(retry)
        )
        retry.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let errorStack = vstack([errorIcon, errorLabel, retry], spacing: 10, alignment: .centerX)
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorStack)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 42),

            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            footerRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            footerRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8),
            footerRow.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: webView.centerYAnchor),

            errorView.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            errorView.widthAnchor.constraint(equalToConstant: 280),
            errorStack.topAnchor.constraint(equalTo: errorView.topAnchor),
            errorStack.leadingAnchor.constraint(equalTo: errorView.leadingAnchor),
            errorStack.trailingAnchor.constraint(equalTo: errorView.trailingAnchor),
            errorStack.bottomAnchor.constraint(equalTo: errorView.bottomAnchor),
        ])
    }

    // MARK: Presentation

    /// Closing during the first load cancels the navigation, so reopen it fresh
    /// rather than showing an empty page.
    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        hasLoaded = false
    }

    func present() {
        guard let window else { return }
        if !hasLoaded { load() }
        if !hasPositioned {
            window.center()
            hasPositioned = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func load() {
        hasLoaded = true
        errorView.isHidden = true
        webView.isHidden = false
        spinner.startAnimation(nil)
        webView.load(URLRequest(url: KoFi.pageURL))
    }

    @objc private func retry() {
        load()
    }

    @objc private func openInBrowser() {
        NSWorkspace.shared.open(KoFi.pageURL)
    }

    private func show(_ error: Error) {
        // A cancelled load is not a failure (closing the window cancels it).
        if (error as NSError).code == NSURLErrorCancelled { return }
        spinner.stopAnimation(nil)
        webView.isHidden = true
        errorView.isHidden = false
        onFailure?(error)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimation(nil)
        errorView.isHidden = true
        onLoad?()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        show(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        show(error)
    }

    // MARK: WKUIDelegate

    /// Payment providers sometimes open a popup for 3-D Secure. Keeping it in
    /// the same web view preserves the checkout instead of dead-ending.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
