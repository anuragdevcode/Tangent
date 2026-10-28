import AppKit
import WebKit

/// Web wallpaper backend (`web`, `webaudio`, `url`).
///
/// Pages run in WKWebView. Control values reach them through the property
/// listener: each value is pushed by calling
/// `window.tangentPropertyListener(name, value)` (or the legacy name), so
/// existing packs work unchanged.
final class WebWallpaper: NSObject, Wallpaper, WKNavigationDelegate {
    let type: WallpaperType
    let view: NSView
    private(set) var isLoaded = false

    private let webView: WKWebView
    private let entry: URL
    private let root: URL?
    private let bindings: [(name: String, value: JSONValue)]
    private var isPaused = false

    /// Fired after the page finishes loading and property defaults are applied.
    var onLoad: (() -> Void)?

    init?(entry: URL, root: URL?, controls: [PropertyControl], title: String, type: WallpaperType) {
        let isRemote = entry.scheme == "http" || entry.scheme == "https"
        if !isRemote, !FileManager.default.fileExists(atPath: entry.path) {
            return nil
        }
        self.entry = entry
        self.root = root
        self.type = type

        let baseFolder = root ?? entry.deletingLastPathComponent()
        self.bindings = PackProperties.bridgeBindings(for: controls, rootFolder: baseFolder)

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Wallpapers must start without a gesture.
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        // Avoid a white flash before first paint.
        webView.setValue(false, forKey: "drawsBackground")
        view = webView

        super.init()

        webView.navigationDelegate = self
        if isRemote {
            webView.load(URLRequest(url: entry))
        } else {
            webView.loadFileURL(entry, allowingReadAccessTo: baseFolder)
        }
    }

    func play() {
        isPaused = false
        evaluate("document.querySelectorAll('video,audio').forEach(function(e){e.play()});")
    }

    func pause() {
        isPaused = true
        evaluate("document.querySelectorAll('video,audio').forEach(function(e){e.pause()});")
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        isLoaded = false
    }

    // MARK: - Control bridge

    /// Applies the property defaults, exactly once per page load.
    private func applyPackProperties() {
        for binding in bindings {
            setProperty(name: binding.name, value: binding.value)
        }
    }

    /// Push a single control value to the page. Used for defaults on load and
    /// available for live control changes later.
    func setProperty(name: String, value: JSONValue) {
        let script = """
        (function(){
          var n = \(JSONValue.quote(name));
          var v = \(value.jsLiteral);
          if (typeof window.\(PackFormat.propertyListener) === 'function') {
            window.\(PackFormat.propertyListener)(n, v);
          } else if (typeof window.\(PackFormat.legacyPropertyListener) === 'function') {
            window.\(PackFormat.legacyPropertyListener)(n, v);
          }
        })();
        """
        evaluate(script)
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script) { _, _ in }
    }

    /// Read-only evaluation hook used by the `--probe-bridge` integration check.
    func evaluateForTesting(_ script: String, completion: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(script) { result, error in
            completion(error == nil ? result : "error: \(error!.localizedDescription)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wallpapers are full-bleed: no scrollbars, no rubber-banding, no
        // text selection (matching wallpaper window behaviour).
        evaluate("""
        var s=document.createElement('style');
        s.textContent='html,body{overflow:hidden;margin:0;padding:0;background:transparent;'+
          '-webkit-user-select:none;cursor:default;}'+
          '::-webkit-scrollbar{display:none;}';
        document.head.appendChild(s);
        """)

        // Property defaults are applied after navigation completes.
        applyPackProperties()

        isLoaded = true
        if !isPaused {
            play()
        }
        onLoad?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Tangent: web wallpaper failed to load: %@", error.localizedDescription)
    }
}
