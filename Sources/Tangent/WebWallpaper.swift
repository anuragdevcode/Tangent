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

    private static let environmentHandler = "tangentEnvironment"

    /// Installed before the pack's own scripts. Pages opt in explicitly by
    /// calling `window.tangent.enableEnvironment()`; until then no timer and no
    /// audio polling run.
    private static let environmentBootstrap = """
    (function () {
      var t = window.tangent = window.tangent || {};
      t.version = 1;
      t.environment = null;
      t.playing = true;
      if (!("onEnvironment" in t)) { t.onEnvironment = null; }
      if (!("onPlaying" in t)) { t.onPlaying = null; }
      t.enableEnvironment = function () {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tangentEnvironment) {
          window.webkit.messageHandlers.tangentEnvironment.postMessage({ command: "enable" });
        }
      };
      t.disableEnvironment = function () {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tangentEnvironment) {
          window.webkit.messageHandlers.tangentEnvironment.postMessage({ command: "disable" });
        }
      };
      t.__setEnvironment = function (state) {
        t.environment = state;
        if (typeof t.onEnvironment === "function") { t.onEnvironment(state); }
      };
      t.__setPlaying = function (playing) {
        t.playing = !!playing;
        if (typeof t.onPlaying === "function") { t.onPlaying(t.playing); }
      };
    })();
    """

    private let webView: WKWebView
    private let entry: URL
    private let root: URL?
    private let bindings: [(name: String, value: JSONValue)]
    private var isPaused = false
    private var isMuted = false

    private var bridge: ScriptBridge?
    private var environmentObserver: UUID?
    private var isEnvironmentEnabled = false
    private var lastEnvironmentSignature = ""
    private var lastEnvironmentSent = Date.distantPast
    private let isRemote: Bool

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
        self.isRemote = isRemote

        let baseFolder = root ?? entry.deletingLastPathComponent()
        self.bindings = PackProperties.bridgeBindings(for: controls, rootFolder: baseFolder)

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Wallpapers must start without a gesture.
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Local packs may opt into ambient state. Remote pages do not get the
        // bridge: pointer, audio presence and appearance stay on this Mac.
        var configuredBridge: ScriptBridge?
        if !isRemote {
            let bridge = ScriptBridge()
            let controller = WKUserContentController()
            controller.addUserScript(WKUserScript(
                source: Self.environmentBootstrap,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            controller.add(bridge, name: Self.environmentHandler)
            configuration.userContentController = controller
            configuredBridge = bridge
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        // Avoid a white flash before first paint.
        webView.setValue(false, forKey: "drawsBackground")
        view = webView

        super.init()

        self.bridge = configuredBridge
        configuredBridge?.owner = self
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
        // Packs that animate in JavaScript stop their own loop from this
        // callback; media elements above are paused separately.
        evaluate("if (window.tangent && window.tangent.__setPlaying) { window.tangent.__setPlaying(true); }")
        if isEnvironmentEnabled {
            startEnvironment()
        }
    }

    func pause() {
        isPaused = true
        evaluate("document.querySelectorAll('video,audio').forEach(function(e){e.pause()});")
        evaluate("if (window.tangent && window.tangent.__setPlaying) { window.tangent.__setPlaying(false); }")
        // Stop the shared ambient timer as well: a paused wallpaper that keeps
        // polling the pointer and audio device is pure waste.
        stopEnvironment()
    }

    /// Mutes all media now and for elements added later. Web wallpapers that
    /// synthesise audio in Web Audio are intentionally left alone: they have no
    /// media element to mute, and cutting the graph would silence the visual
    /// reaction too.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        evaluate(Self.muteScript(muted: muted))
    }

    func close() {
        stopEnvironment()
        isEnvironmentEnabled = false
        bridge?.owner = nil
        bridge = nil
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.environmentHandler)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        isLoaded = false
    }

    // MARK: - Environment bridge

    /// Ambient state, opt-in from the page.
    ///
    /// A pack calls `window.tangent.enableEnvironment()` once and gets an
    /// `EnvironmentSnapshot`-shaped object on `window.tangent.onEnvironment`.
    /// Values are local to this Mac and are never sent anywhere.
    private func setEnvironmentEnabled(_ enabled: Bool) {
        guard bridge != nil, !isRemote else { return }
        isEnvironmentEnabled = enabled
        if enabled, !isPaused {
            startEnvironment()
        } else {
            stopEnvironment()
        }
    }

    private func startEnvironment() {
        guard environmentObserver == nil else { return }
        environmentObserver = EnvironmentMonitor.shared.addObserver { [weak self] snapshot in
            self?.push(environment: snapshot)
        }
    }

    private func stopEnvironment() {
        guard let environmentObserver else { return }
        EnvironmentMonitor.shared.removeObserver(environmentObserver)
        self.environmentObserver = nil
    }

    private func push(environment: EnvironmentSnapshot) {
        guard isLoaded, environmentObserver != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastEnvironmentSent) >= 1.0 / 30.0 else { return }

        let pointer = normalizedPointer(for: environment)
        // Round before comparing so a stationary pointer at 30 Hz does not
        // re-send an identical payload every frame.
        let x = (pointer.point.x * 1000).rounded() / 1000
        let y = (pointer.point.y * 1000).rounded() / 1000
        let day = (environment.dayPhase * 1440).rounded() / 1440
        let signature = "\(x),\(y),\(pointer.inside),\(environment.isAudioPlaying),\(environment.isDark),\(environment.reduceMotion),\(environment.lowPowerMode),\(day)"
        guard signature != lastEnvironmentSignature else { return }

        lastEnvironmentSignature = signature
        lastEnvironmentSent = now

        let payload = """
        {"version":1,"pointer":{"x":\(Self.number(x)),"y":\(Self.number(y))},"pointerInside":\(pointer.inside),\
        "audioPlaying":\(environment.isAudioPlaying),"dayPhase":\(Self.number(day)),\
        "dark":\(environment.isDark),"reduceMotion":\(environment.reduceMotion),\
        "lowPowerMode":\(environment.lowPowerMode),"timestamp":\(Self.number(environment.timestamp))}
        """
        evaluate("if (window.tangent && window.tangent.__setEnvironment) { window.tangent.__setEnvironment(\(payload)); }")
    }

    /// Pointer in this view's own 0…1 coordinates, top-left origin, so a pack
    /// behaves the same on the desktop, in the inspector preview and in the
    /// screen saver.
    private func normalizedPointer(for environment: EnvironmentSnapshot) -> (point: CGPoint, inside: Bool) {
        let screenFrame: CGRect
        if let window = webView.window {
            screenFrame = window.convertToScreen(webView.convert(webView.bounds, to: nil))
        } else {
            screenFrame = NSScreen.main?.frame ?? .zero
        }
        return PointerGeometry.normalized(point: environment.pointerScreen, in: screenFrame)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4f", value)
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

    /// Keeps media elements muted and remembers the setting for elements the
    /// page adds later.
    private static func muteScript(muted: Bool) -> String {
        let flag = muted ? "true" : "false"
        return """
        (function(){
          window.__tangentMuted = \(flag);
          function apply(){document.querySelectorAll('video,audio').forEach(function(e){e.muted=window.__tangentMuted;});}
          apply();
          if (!window.__tangentMuteObserver) {
            window.__tangentMuteObserver = new MutationObserver(function(){
              if (window.__tangentMuted) { apply(); }
            });
            window.__tangentMuteObserver.observe(document.documentElement, {childList:true, subtree:true});
          }
        })();
        """
    }

    /// Read-only evaluation hook used by the `--probe-bridge` integration check.
    func evaluateForTesting(_ script: String, completion: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(script) { result, error in
            completion(error == nil ? result : "error: \(error!.localizedDescription)")
        }
    }

    /// Renders the current page to an image. Used to generate first-party pack
    /// thumbnails so the gallery shows the real wallpaper rather than a guess.
    func takeSnapshot(width: CGFloat? = nil, completion: @escaping (NSImage?) -> Void) {
        let configuration = WKSnapshotConfiguration()
        if let width {
            configuration.snapshotWidth = NSNumber(value: Double(width))
        }
        webView.takeSnapshot(with: configuration) { image, error in
            if let error {
                NSLog("Tangent: wallpaper snapshot failed: %@", error.localizedDescription)
            }
            completion(image)
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
        if isMuted {
            evaluate(Self.muteScript(muted: true))
        }

        isLoaded = true
        // A reload starts a new page; let it receive the next snapshot even if
        // it is identical to the one the previous page saw.
        lastEnvironmentSignature = ""
        if !isPaused {
            play()
        }
        onLoad?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Tangent: web wallpaper failed to load: %@", error.localizedDescription)
    }
}

/// Receives opt-in messages from a local pack's page.
///
/// The controller retains this object, so it keeps only a weak reference back
/// to the wallpaper; otherwise the web view would outlive every `close()`.
final class ScriptBridge: NSObject, WKScriptMessageHandler {
    weak var owner: WebWallpaper?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }
        switch command {
        case "enable":
            owner?.handleBridgeCommand(.enableEnvironment)
        case "disable":
            owner?.handleBridgeCommand(.disableEnvironment)
        default:
            break
        }
    }
}

extension WebWallpaper {
    enum BridgeCommand {
        case enableEnvironment
        case disableEnvironment
    }

    func handleBridgeCommand(_ command: BridgeCommand) {
        switch command {
        case .enableEnvironment:
            setEnvironmentEnabled(true)
        case .disableEnvironment:
            setEnvironmentEnabled(false)
        }
    }
}
