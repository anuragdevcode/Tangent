import AppKit
import WebKit

// MARK: - Diagnostics

private struct ScreenInfo: Codable {
    var displayID: UInt32
    var frame: String
    var scale: Double
}

private struct SelfTestReport: Codable {
    var ok: Bool
    var arch: String
    var macOS: String
    var screenCount: Int
    var screens: [ScreenInfo]
    var desktopWindowLevel: Int
    var desktopIconWindowLevel: Int
    var supportedTypes: [String]
    var unsupportedTypes: [String]
    var defaultLibraryPath: String
}

private func machineArch() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: &info.machine) { raw in
        guard let base = raw.baseAddress else { return "unknown" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }
}

private func displayID(of screen: NSScreen) -> UInt32 {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
}

/// Headless verification: proves desktop window levels, screen enumeration and
/// type support without needing a visible display.
private func runSelfTest() {
    let screens = NSScreen.screens.map { screen in
        ScreenInfo(
            displayID: displayID(of: screen),
            frame: NSStringFromRect(screen.frame),
            scale: Double(screen.backingScaleFactor)
        )
    }

    let allTypes: [WallpaperType] = [
        .app, .web, .webaudio, .url, .bizhawk, .unity, .godot,
        .video, .gif, .unityaudio, .videostream, .picture
    ]

    let report = SelfTestReport(
        ok: true,
        arch: machineArch(),
        macOS: ProcessInfo.processInfo.operatingSystemVersionString,
        screenCount: screens.count,
        screens: screens,
        desktopWindowLevel: Int(CGWindowLevelForKey(.desktopWindow)),
        desktopIconWindowLevel: Int(CGWindowLevelForKey(.desktopIconWindow)),
        supportedTypes: allTypes.filter(\.isSupported).map(\.rawValue),
        unsupportedTypes: allTypes.filter { !$0.isSupported }.map(\.rawValue),
        defaultLibraryPath: PackLibrary.defaultRoot.path
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

// MARK: - Control-bridge probe

/// End-to-end check that property defaults reach a real page through the
/// page-side property listener.
private func runBridgeProbe(folderPath: String) -> Never {
    let folder = URL(fileURLWithPath: folderPath)
    let entry = folder.appendingPathComponent("index.html")
    // Same path the wallpaper factory uses: customised copy first, then the pack.
    let controls = PropertyStore.shared.controls(forRoot: folder)

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    guard let wallpaper = WebWallpaper(
        entry: entry,
        root: folder,
        controls: controls,
        title: "probe",
        type: .web
    ) else {
        print("PROBE FAIL: cannot create web wallpaper at \(entry.path)")
        exit(1)
    }

    var finished = false
    wallpaper.onLoad = {
        wallpaper.evaluateForTesting("JSON.stringify(window.__packCalls||[])") { result in
            print(result as? String ?? "PROBE FAIL: no result")
            finished = true
        }
    }

    withExtendedLifetime(wallpaper) {
        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
    exit(finished ? 0 : 1)
}

// MARK: - libmpv probe

/// Proves libmpv decodes a VP9/WebM/AV1 file *and* renders frames through the
/// same OpenGL path the desktop wallpaper uses.
private func runMPVProbe(path: String) -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    guard let wallpaper = MPVWallpaper(url: URL(fileURLWithPath: path), muted: true) else {
        printJSON(["ok": false, "error": "cannot create mpv wallpaper"])
        exit(1)
    }

    let window = NSWindow(
        contentRect: NSRect(x: 60, y: 60, width: 480, height: 270),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = wallpaper.view
    window.orderFrontRegardless()
    wallpaper.play()

    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if wallpaper.renderedFrames >= 10, let size = wallpaper.videoSize {
            printJSON([
                "ok": true,
                "codec": wallpaper.codecName ?? "unknown",
                "width": Int(size.width),
                "height": Int(size.height),
                "frames": wallpaper.renderedFrames,
                "renderError": Int(wallpaper.lastRenderError),
                "library": wallpaper.libraryPath,
            ])
            wallpaper.close()
            exit(0)
        }
    }

    printJSON([
        "ok": false,
        "codec": wallpaper.codecName ?? "unknown",
        "width": wallpaper.videoSize.map { Int($0.width) } ?? 0,
        "height": wallpaper.videoSize.map { Int($0.height) } ?? 0,
        "frames": wallpaper.renderedFrames,
        "renderError": Int(wallpaper.lastRenderError),
        "library": wallpaper.libraryPath,
    ])
    wallpaper.close()
    exit(1)
}

private func printJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else { return }
    print(text)
}

// MARK: - Hotkey probe

/// Proves Carbon registration works without changing the saved preference.
/// Exits non-zero if any shortcut could not be registered.
private func runHotkeyProbe() -> Never {
    let manager = HotkeyManager()
    manager.registerForDiagnostics()

    let failures = manager.failures.map { action, status in
        [action.rawValue, String(status)]
    }
    let allRegistered = manager.registeredActions.count == HotkeyManager.Action.allCases.count
    let ok = allRegistered && manager.handlerStatus == noErr
    printJSON([
        "ok": ok,
        "preferenceEnabled": manager.isEnabled,
        "handlerStatus": Int(manager.handlerStatus),
        "registered": manager.registeredActions.map(\.rawValue),
        "failures": failures,
        "shortcuts": Dictionary(
            uniqueKeysWithValues: HotkeyManager.Action.allCases.map {
                ($0.rawValue, manager.binding(for: $0).display)
            }
        ),
        "defaults": Dictionary(
            uniqueKeysWithValues: HotkeyManager.Action.allCases.map {
                ($0.rawValue, $0.defaultBinding.display)
            }
        ),
        "customized": manager.bindings.keys.map(\.rawValue).sorted(),
    ])
    manager.stop()
    exit(ok ? 0 : 1)
}

// MARK: - Ko-fi probe

/// Proves the real support window can load the Ko-fi page, and reports its
/// title, login state and visible text. An optional path captures the page.
private func runKoFiProbe(snapshotPath: String?) -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let controller = KoFiSupportWindowController.makeForProbe()
    var report: [String: Any] = [
        "ok": false,
        "url": KoFi.pageURL.absoluteString,
    ]
    var evaluated = false
    var captured = snapshotPath == nil

    controller.onFailure = { error in
        guard !evaluated else { return }
        report["error"] = error.localizedDescription
        evaluated = true
        captured = true
    }

    controller.onLoad = {
        controller.webView.evaluateJavaScript("""
        (() => {
          const text = (document.body && document.body.innerText) || '';
          return JSON.stringify({
            title: document.title || '',
            textLength: text.length,
            mentionsKoFi: /ko-fi/i.test(text),
            mentionsSupport: /support|tip|coffee|buy/i.test(text),
            loggedIn: /log out/i.test(text),
            bodyPreview: text.replace(/\\s+/g, ' ').trim().slice(0, 160)
          });
        })()
        """) { result, error in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                report["ok"] = true
                report.merge(parsed) { _, new in new }
                if let window = controller.window {
                    report["window"] = NSStringFromRect(window.frame)
                }
            } else if let error {
                report["error"] = error.localizedDescription
            } else {
                report["error"] = "no page report"
            }
            evaluated = true

            guard let snapshotPath else { return }
            let url = URL(fileURLWithPath: snapshotPath)
            controller.webView.takeSnapshot(with: nil) { image, snapshotError in
                if let tiff = image?.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                    report["snapshot"] = url.path
                } else if let snapshotError {
                    report["snapshotError"] = snapshotError.localizedDescription
                }
                captured = true
            }
        }
    }

    controller.present()

    let deadline = Date().addingTimeInterval(30)
    while !(evaluated && captured) && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    if !evaluated, report["error"] == nil {
        report["error"] = "timed out waiting for \(KoFi.pageURL.absoluteString)"
    }

    withExtendedLifetime(controller) {
        printJSON(report)
    }
    exit(report["ok"] as? Bool == true ? 0 : 1)
}

// MARK: - Entry point

let arguments = CommandLine.arguments

if let flagIndex = arguments.firstIndex(of: "--probe-bridge"), arguments.count > flagIndex + 1 {
    runBridgeProbe(folderPath: arguments[flagIndex + 1])
}

if let flagIndex = arguments.firstIndex(of: "--probe-mpv"), arguments.count > flagIndex + 1 {
    runMPVProbe(path: arguments[flagIndex + 1])
}

if let flagIndex = arguments.firstIndex(of: "--probe-kofi") {
    let snapshot = arguments.count > flagIndex + 1 && !arguments[flagIndex + 1].hasPrefix("--")
        ? arguments[flagIndex + 1]
        : nil
    runKoFiProbe(snapshotPath: snapshot)
}

if arguments.contains("--hotkey-status") {
    runHotkeyProbe()
}

if arguments.contains("--test") {
    exit(SelfTests.run())
}

if arguments.contains("--selftest") {
    runSelfTest()
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()

// Scripted/automatable entry point: `Tangent --set <file-or-folder>`.
// `--display N` pins the wallpaper to the Nth display (1-based).
// `--ephemeral` keeps the run out of the user's saved layout.
if let flagIndex = arguments.firstIndex(of: "--set"), arguments.count > flagIndex + 1 {
    let path = arguments[flagIndex + 1]
    let url = URL(fileURLWithPath: path)

    guard let pack = Pack.synthetic(fileURL: url) else {
        FileHandle.standardError.write(Data("Unsupported wallpaper: \(path)\n".utf8))
        exit(2)
    }
    if let reason = pack.unsupportedReason {
        FileHandle.standardError.write(Data("Cannot use \(path): \(reason)\n".utf8))
        exit(3)
    }
    appDelegate.initialPack = pack

    if let displayIndex = arguments.firstIndex(of: "--display"),
       arguments.count > displayIndex + 1,
       let index = Int(arguments[displayIndex + 1]) {
        appDelegate.initialDisplayIndex = index
    }
}

appDelegate.persistSelection = !arguments.contains("--ephemeral")

application.delegate = appDelegate

if arguments.contains("--library") {
    appDelegate.openLibraryOnLaunch = true
}

if let flagIndex = arguments.firstIndex(of: "--snapshot-library"),
   arguments.count > flagIndex + 1 {
    appDelegate.openLibraryOnLaunch = true
    appDelegate.snapshotPath = arguments[flagIndex + 1]
}

if let flagIndex = arguments.firstIndex(of: "--snapshot-properties"),
   arguments.count > flagIndex + 1 {
    appDelegate.snapshotPropertiesPath = arguments[flagIndex + 1]
}

if let flagIndex = arguments.firstIndex(of: "--snapshot-settings"),
   arguments.count > flagIndex + 1 {
    appDelegate.snapshotSettingsPath = arguments[flagIndex + 1]
}

if let flagIndex = arguments.firstIndex(of: "--snapshot-popover"),
   arguments.count > flagIndex + 1 {
    appDelegate.snapshotPopoverPath = arguments[flagIndex + 1]
}

if let flagIndex = arguments.firstIndex(of: "--settings-pane"),
   arguments.count > flagIndex + 1,
   let index = Int(arguments[flagIndex + 1]) {
    appDelegate.settingsPaneIndex = index
}

if let flagIndex = arguments.firstIndex(of: "--library-section"),
   arguments.count > flagIndex + 1,
   let index = Int(arguments[flagIndex + 1]) {
    appDelegate.librarySectionIndex = index
}

if let flagIndex = arguments.firstIndex(of: "--gallery-search"),
   arguments.count > flagIndex + 1 {
    appDelegate.gallerySearch = arguments[flagIndex + 1]
}

if let flagIndex = arguments.firstIndex(of: "--gallery-select"),
   arguments.count > flagIndex + 1,
   let index = Int(arguments[flagIndex + 1]) {
    appDelegate.gallerySelectionIndex = index
}

if let flagIndex = arguments.firstIndex(of: "--report-frames"),
   arguments.count > flagIndex + 1,
   let seconds = Double(arguments[flagIndex + 1]) {
    appDelegate.frameReportDelay = seconds
}

// Accessory: menu bar only, no Dock icon and no focus stealing.
application.setActivationPolicy(.accessory)
application.run()
