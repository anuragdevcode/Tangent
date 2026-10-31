import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Parser and library tests, runnable without XCTest:
/// `./build/Tangent.app/Contents/MacOS/Tangent --test`
///
/// These exist because the whole point of Phase 2 is byte-level compatibility
/// with files produced by another program, which is exactly where assumptions
/// silently go wrong.
enum SelfTests {

    static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Diagnostics
            .deletingLastPathComponent()   // Tangent
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // project root
            .appendingPathComponent("Tests/Fixtures")
    }

    static func run() -> Int32 {
        var failures = 0
        var checks = 0

        func expect(_ condition: Bool, _ label: String) {
            checks += 1
            if condition {
                print("  ok    \(label)")
            } else {
                failures += 1
                print("  FAIL  \(label)")
            }
        }

        // MARK: JSONValue

        print("JSONValue")
        let json = try? JSONValue.load(from: fixturesRoot
            .appendingPathComponent("library/landing-web/\(PackFormat.propertiesFile)"))
        expect(json != nil, "loads a control file")
        expect(json?.value(forKey: "SPEED") != nil, "case-insensitive key lookup")
        // Compare the exact enum case: this also proves booleans are not
        // silently decoded as numbers (NSNumber covers both).
        expect(json?.value(forKey: "flip")?.value(forKey: "value") == .bool(true), "booleans decode as bool")
        expect(json?.value(forKey: "speed")?.value(forKey: "value") == .number(1.5), "numbers decode as number")
        expect(json?.value(forKey: "caption")?.value(forKey: "value") == .string("Hello"), "strings decode")
        expect(json?.value(forKey: "nope") == nil, "missing keys return nil")

        // MARK: PackInfo

        print("PackInfo")
        let videoPack = try? Pack.load(folder: fixturesRoot
            .appendingPathComponent("library/aurora-video"))
        expect(videoPack != nil, "loads a pack info file")
        expect(videoPack?.info.title == "Aurora Drift", "reads Title")
        expect(videoPack?.info.type == .video, "reads Type")
        expect(videoPack?.info.author == "Studio Nord", "reads Author")
        expect(videoPack?.info.tags == ["abstract", "loop"], "reads Tags array")
        expect(videoPack?.entryURL?.lastPathComponent == "aurora.mp4", "resolves relative FileName")
        expect(videoPack?.thumbnailURL?.lastPathComponent == "thumb.jpg", "resolves relative Thumbnail")
        expect(videoPack?.unsupportedReason == nil, "supported video pack reports no reason")

        let absoluteInfo = """
        {"Title":"Abs","Type":"picture","FileName":"/tmp/abs.png","IsAbsolutePath":true}
        """
        if let data = absoluteInfo.data(using: .utf8),
           let any = try? JSONSerialization.jsonObject(with: data),
           let value = JSONValue(any: any) {
            let info = PackInfo.parse(value, fallbackTitle: "fallback")
            expect(info.isAbsolutePath, "reads IsAbsolutePath")
            let pack = Pack(folder: URL(fileURLWithPath: "/tmp"), info: info)
            expect(pack.entryURL?.path == "/tmp/abs.png", "absolute FileName is not re-rooted")
        } else {
            expect(false, "absolute-path fixture parses")
        }

        let missingTitle = PackInfo.parse(.object([:]), fallbackTitle: "Folder Name")
        expect(missingTitle.title == "Folder Name", "falls back to folder name when Title is absent")

        // Library identity: a real pack is added by folder, a dragged-in file by
        // the file itself (adding its parent folder would import unrelated files).
        expect(videoPack?.libraryEntry == videoPack?.folder,
               "a real pack adds its folder to the library")
        let bareFile = Pack.synthetic(
            fileURL: fixturesRoot.appendingPathComponent("library/aurora-video/aurora.mp4")
        )
        expect(bareFile?.libraryEntry.lastPathComponent == "aurora.mp4",
               "a bare file adds the file, not its parent folder")
        expect(bareFile?.folder.lastPathComponent == "aurora-video",
               "a bare file still resolves its containing folder")
        let bareWebM = Pack.synthetic(
            fileURL: fixturesRoot.appendingPathComponent("media/vp9.webm")
        )
        expect(bareWebM?.info.type == .video, "a bare .webm file is recognised as video")
        expect(bareWebM?.unsupportedReason == nil, "a bare .webm file has a playable entry")

        // MARK: WallpaperType

        print("WallpaperType")
        expect(WallpaperType(raw: "web").isSupported, "web is supported")
        expect(WallpaperType(raw: "webaudio").isSupported, "webaudio is supported")
        expect(WallpaperType(raw: "video").isSupported, "video is supported")
        expect(WallpaperType(raw: "gif").isSupported, "gif is supported")
        expect(WallpaperType(raw: "picture").isSupported, "picture is supported")
        expect(!WallpaperType(raw: "unity").isSupported, "unity is unsupported")
        expect(!WallpaperType(raw: "app").isSupported, "app is unsupported")
        expect(!WallpaperType(raw: "bizhawk").isSupported, "bizhawk is unsupported")
        expect(WallpaperType(raw: "hologram") == .unknown("hologram"), "unknown types are preserved")
        expect(!WallpaperType(raw: "hologram").isSupported, "unknown types are unsupported")

        // MARK: Video routing

        print("Video routing")
        let mediaRoot = fixturesRoot.appendingPathComponent("media")
        expect(VideoRouting.codecFourCC(for: mediaRoot.appendingPathComponent("h264.mp4")) == "avc1",
               "reads H.264 FourCC from MP4")
        expect(VideoRouting.codecFourCC(for: mediaRoot.appendingPathComponent("vp9.mp4")) == "vp09",
               "reads VP9 FourCC from MP4")
        expect(VideoRouting.codecFourCC(for: mediaRoot.appendingPathComponent("av1.mp4")) == "av01",
               "reads AV1 FourCC from MP4")
        expect(VideoRouting.backend(for: mediaRoot.appendingPathComponent("h264.mp4")) == .avFoundation,
               "H.264 stays on AVFoundation")
        expect(VideoRouting.backend(for: mediaRoot.appendingPathComponent("vp9.webm")) == .mpv,
               "WebM goes to libmpv")
        expect(VideoRouting.backend(for: mediaRoot.appendingPathComponent("vp9.mp4")) == .mpv,
               "VP9 inside MP4 goes to libmpv")
        expect(VideoRouting.backend(for: mediaRoot.appendingPathComponent("av1.mp4")) == .mpv,
               "AV1 inside MP4 goes to libmpv")
        expect(VideoRouting.backend(for: URL(fileURLWithPath: "/tmp/clip.mkv")) == .mpv,
               "Matroska goes to libmpv by extension")

        // MARK: Bundled libmpv

        print("Bundled libmpv")
        let bundledLibmpv = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/libmpv.2.dylib")
        let overrideSet = ProcessInfo.processInfo.environment["TANGENT_LIBMPV"] != nil
        if !overrideSet, FileManager.default.fileExists(atPath: bundledLibmpv.path) {
            expect(MPVAPI.shared?.path == bundledLibmpv.path,
                   "bundled libmpv is preferred over Homebrew")
            expect(MPVAPI.shared?.path.hasPrefix(Bundle.main.bundlePath) == true,
                   "libmpv loads from inside the app bundle")
        }

        // MARK: PackProperties

        print("PackProperties")
        let controls = PackProperties.load(folder: fixturesRoot
            .appendingPathComponent("library/landing-web"))
        expect(controls.count == 9, "parses all nine control entries")
        expect(controls.first(where: { $0.name == "speed" })?.spec.kindName == "slider", "slider control")
        expect(controls.first(where: { $0.name == "caption" })?.spec.kindName == "textbox", "textbox control")
        expect(controls.first(where: { $0.name == "mode" })?.spec.kindName == "dropdown", "dropdown control")
        expect(controls.first(where: { $0.name == "image" })?.spec.kindName == "folderDropdown", "folderDropdown control")
        expect(controls.first(where: { $0.name == "apply" })?.spec.kindName == "button", "button control")
        expect(controls.first(where: { $0.name == "note" })?.spec.kindName == "label", "label control")
        expect(controls.first(where: { $0.name == "tint" })?.spec.kindName == "color", "color control")
        expect(controls.first(where: { $0.name == "flip" })?.spec.kindName == "checkbox", "checkbox control")

        if case .slider(_, let min, let max, let step, let value)? =
            controls.first(where: { $0.name == "speed" })?.spec {
            expect(min == 0 && max == 5 && step == 0.1 && value == 1.5, "slider bounds and default value")
        } else {
            expect(false, "slider bounds parse")
        }
        if case .dropdown(_, let items, let value)? =
            controls.first(where: { $0.name == "mode" })?.spec {
            expect(items == ["One", "Two", "Three"] && value == 1, "dropdown items and default index")
        } else {
            expect(false, "dropdown items parse")
        }

        let root = fixturesRoot.appendingPathComponent("library/landing-web")
        let bindings = PackProperties.bridgeBindings(for: controls, rootFolder: root)
        expect(bindings.count == 7, "button and label are excluded from the bridge")
        let byName = Dictionary(uniqueKeysWithValues: bindings.map { ($0.name, $0.value) })
        expect(byName["speed"] == .number(1.5), "slider value pushed as number")
        expect(byName["mode"] == .number(1), "dropdown index pushed as number")
        expect(byName["flip"] == .bool(true), "checkbox pushed as bool")
        expect(byName["tint"] == .string("#112233"), "color pushed as string")
        expect(byName["image"] == .string("present.jpg"), "existing folderDropdown file sent as name")
        expect(byName["missingImage"] == .null, "missing folderDropdown file sent as null")
        expect(byName["apply"] == nil, "button omitted")
        expect(JSONValue.string("a\"b\nc").jsLiteral == "\"a\\\"b\\nc\"", "JS string escaping")

        // MARK: Library scan

        print("Library scan")
        let suiteName = "tangent.tests"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        // Keep the scan off the user's real library; a local wallpaper there
        // would otherwise change every count in this section.
        let scratchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tangent-test-library", isDirectory: true)
        let library = PackLibrary(defaults: defaults, fallbackRoot: scratchRoot)
        library.addRoot(fixturesRoot.appendingPathComponent("library"))
        let packs = library.scan()

        expect(packs.count == 4, "scans four packs (got \(packs.count))")
        expect(packs.contains { $0.info.title == "Aurora Drift" }, "finds video pack")
        expect(packs.contains { $0.info.title == "Landing Page" }, "finds web pack")
        expect(packs.contains { $0.info.title == "Godot Space" }, "finds unsupported pack")
        expect(!packs.contains { $0.folder.lastPathComponent == "notes.txt" }, "ignores non-wallpaper files")

        let godot = packs.first { $0.info.title == "Godot Space" }
        expect(godot?.unsupportedReason != nil, "unsupported pack carries a reason")
        let web = packs.first { $0.info.title == "Landing Page" }
        expect(web?.entryURL?.lastPathComponent == "index.html", "web pack resolves index.html")
        expect(web?.unsupportedReason == nil, "web pack is usable")

        // Removing a pack hides it from the library; the files stay on disk and
        // restoring brings it back.
        if let aurora = packs.first(where: { $0.info.title == "Aurora Drift" }) {
            library.hide(aurora)
            expect(library.isHidden(aurora), "hide marks a pack hidden")
            expect(!library.scan().contains { $0.id == aurora.id }, "hidden pack leaves the scan")
            expect(FileManager.default.fileExists(atPath: aurora.folder.path),
                   "hiding keeps the pack folder on disk")
            library.restoreHidden()
            expect(library.scan().contains { $0.id == aurora.id }, "restore brings the pack back")
        } else {
            expect(false, "fixture pack available for hide/restore checks")
        }

        // MARK: Multiple wallpapers in one folder

        print("Library additions")
        let addSuite = "tangent.tests.additions"
        UserDefaults.standard.removePersistentDomain(forName: addSuite)
        let addDefaults = UserDefaults(suiteName: addSuite)!
        let dropFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tangent-test-drop", isDirectory: true)
        try? FileManager.default.removeItem(at: dropFolder)
        try? FileManager.default.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        let firstFile = dropFolder.appendingPathComponent("first.mp4")
        let secondFile = dropFolder.appendingPathComponent("second.mp4")
        let fixtureVideo = fixturesRoot.appendingPathComponent("library/aurora-video/aurora.mp4")
        try? FileManager.default.copyItem(at: fixtureVideo, to: firstFile)
        try? FileManager.default.copyItem(at: fixtureVideo, to: secondFile)

        let addLibrary = PackLibrary(defaults: addDefaults, fallbackRoot: dropFolder)
        let addModel = LibraryModel(library: addLibrary, defaults: addDefaults)
        addModel.add(contentsOf: [firstFile, secondFile])
        expect(addModel.packs.count == 2, "adds two files from one folder (got \(addModel.packs.count))")
        expect(Set(addModel.packs.map(\.id)).count == 2, "each file keeps its own identity")
        expect(addModel.packs.allSatisfy { $0.libraryEntry != dropFolder },
               "a bare file is identified by the file, not its folder")

        // Adding a plain folder adopts the videos inside it.
        let folderRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tangent-test-folder", isDirectory: true)
        try? FileManager.default.removeItem(at: folderRoot)
        try? FileManager.default.createDirectory(at: folderRoot, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: fixtureVideo, to: folderRoot.appendingPathComponent("one.mp4"))
        try? FileManager.default.copyItem(at: fixtureVideo, to: folderRoot.appendingPathComponent("two.mp4"))
        let folderSuite = "tangent.tests.folder"
        UserDefaults.standard.removePersistentDomain(forName: folderSuite)
        let folderDefaults = UserDefaults(suiteName: folderSuite)!
        let folderLibrary = PackLibrary(defaults: folderDefaults, fallbackRoot: folderRoot)
        let folderModel = LibraryModel(library: folderLibrary, defaults: folderDefaults)
        folderModel.add(contentsOf: [folderRoot])
        expect(folderModel.packs.count == 2, "adding a folder discovers the videos inside")
        expect(folderModel.packs.allSatisfy { $0.info.type == .video }, "discovered files keep their type")

        try? FileManager.default.removeItem(at: dropFolder)
        try? FileManager.default.removeItem(at: folderRoot)

        // MARK: Gallery query

        print("Gallery query")
        expect(LibraryQuery().apply(to: packs).count == 4, "empty query returns every pack")
        expect(LibraryQuery(search: "aurora").apply(to: packs).map(\.info.title) == ["Aurora Drift"],
               "search matches the title")
        expect(LibraryQuery(search: "AURORA").apply(to: packs).count == 1,
               "search is case-insensitive")
        expect(LibraryQuery(search: "Studio Nord").apply(to: packs).count == 1,
               "search matches the author")
        expect(LibraryQuery(search: "night sky").apply(to: packs).count == 1,
               "search matches the summary")
        expect(LibraryQuery(search: "abstract").apply(to: packs).count == 1,
               "search matches tags")
        expect(LibraryQuery(search: "   ").apply(to: packs).count == 4,
               "whitespace-only search is ignored")
        expect(LibraryQuery(filter: .video).apply(to: packs).count == 1, "video filter")
        expect(LibraryQuery(filter: .web).apply(to: packs).count == 1, "web filter")
        expect(LibraryQuery(filter: .images).apply(to: packs).isEmpty, "image filter has no fixtures")
        expect(LibraryQuery(filter: .unsupported).apply(to: packs).count == 2,
               "unsupported filter includes unknown types")
        expect(LibraryQuery(search: "godot", filter: .unsupported).apply(to: packs).count == 1,
               "search and filter combine")
        expect(LibraryQuery(search: "godot", filter: .video).apply(to: packs).isEmpty,
               "filter excludes non-matching packs even when the search matches")

        // MARK: Wallpaper cycling

        print("Wallpaper cycling")
        let playable = packs.filter { $0.unsupportedReason == nil }
        expect(playable.count == 2, "two playable fixtures")
        let first = WallpaperCycler.next(after: nil, in: packs)
        expect(first?.id == playable.first?.id, "cycling starts at the first playable pack")
        let second = WallpaperCycler.next(after: first, in: packs)
        expect(second?.id == playable.last?.id, "cycling advances to the next playable pack")
        expect(WallpaperCycler.next(after: second, in: packs)?.id == playable.first?.id,
               "cycling wraps around")
        expect(WallpaperCycler.next(after: first, in: packs, forward: false)?.id == playable.last?.id,
               "cycling can go backwards")
        expect(WallpaperCycler.next(after: nil, in: []) == nil, "no wallpapers means no next")
        expect(WallpaperCycler.next(after: nil, in: packs.filter { $0.unsupportedReason != nil }) == nil,
               "unsupported-only library has no next")

        // MARK: Global hotkeys

        print("Global hotkeys")
        let actions = HotkeyManager.Action.allCases
        expect(actions.count == 4, "four global shortcuts")
        expect(Set(actions.map(\.display)).count == 4, "shortcut combinations are unique")
        expect(Set(actions.map(\.identifier)).count == 4, "hotkey IDs are unique")
        expect(actions.allSatisfy { !$0.title.isEmpty }, "every shortcut has a title")
        expect(actions.allSatisfy { $0.display.hasPrefix("⌃⌥") }, "shortcuts use Control-Option")
        expect(HotkeyManager.Action.action(for: HotkeyManager.Action.openLibrary.identifier) == .openLibrary,
               "hotkey IDs resolve back to actions")
        expect(HotkeyManager.Action.action(for: 99) == nil, "unknown hotkey IDs are ignored")

        let hotkeySuite = "tangent.hotkey.tests"
        UserDefaults.standard.removePersistentDomain(forName: hotkeySuite)
        let hotkeyDefaults = UserDefaults(suiteName: hotkeySuite)!
        let hotkeys = HotkeyManager(defaults: hotkeyDefaults)
        expect(!hotkeys.isEnabled, "global shortcuts default to off")
        expect(!hotkeys.isActive, "nothing is registered while disabled")
        expect(hotkeys.statusDescription.contains("off"), "disabled status is explained")

        expect(hotkeys.binding(for: .togglePause) == HotkeyManager.Action.togglePause.defaultBinding,
               "manager starts with the default binding")
        expect(!hotkeys.isCustomized(.togglePause), "default binding is not marked custom")
        expect(hotkeys.bindings.isEmpty, "no custom bindings are stored initially")

        let custom = HotkeyManager.KeyBinding(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | shiftKey)
        )
        expect(custom.display == "⌃⇧K", "custom binding formats its modifiers and key")
        try? hotkeys.setBinding(custom, for: .openLibrary)
        expect(hotkeys.binding(for: .openLibrary) == custom, "custom binding is applied")
        expect(hotkeys.isCustomized(.openLibrary), "custom binding is marked customized")

        let reloaded = HotkeyManager(defaults: hotkeyDefaults)
        expect(reloaded.binding(for: .openLibrary) == custom,
               "custom binding persists across instances")

        do {
            try reloaded.setBinding(reloaded.binding(for: .openLibrary), for: .nextWallpaper)
            expect(false, "duplicate bindings are rejected")
        } catch let error as HotkeyManager.BindingError {
            expect(error == .duplicate(.openLibrary), "duplicate reports the conflicting action")
        } catch {
            expect(false, "duplicate throws a BindingError")
        }

        do {
            try reloaded.setBinding(
                HotkeyManager.KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: 0),
                for: .nextWallpaper
            )
            expect(false, "bindings without Control or Option are rejected")
        } catch let error as HotkeyManager.BindingError {
            expect(error == .missingModifier, "missing modifier is explained")
        } catch {
            expect(false, "missing modifier throws a BindingError")
        }

        do {
            try reloaded.setBinding(
                HotkeyManager.KeyBinding(
                    keyCode: UInt32(kVK_Command),
                    modifiers: UInt32(controlKey | optionKey)
                ),
                for: .nextWallpaper
            )
            expect(false, "modifier-only bindings are rejected")
        } catch let error as HotkeyManager.BindingError {
            expect(error == .modifierOnly, "modifier-only binding is explained")
        } catch {
            expect(false, "modifier-only throws a BindingError")
        }

        do {
            try reloaded.setBinding(
                HotkeyManager.KeyBinding(
                    keyCode: UInt32(kVK_Escape),
                    modifiers: UInt32(controlKey | optionKey)
                ),
                for: .nextWallpaper
            )
            expect(false, "Escape is reserved")
        } catch let error as HotkeyManager.BindingError {
            expect(error == .reservedKey("Escape"), "reserved key is explained")
        } catch {
            expect(false, "reserved key throws a BindingError")
        }

        reloaded.resetBinding(for: .openLibrary)
        expect(reloaded.binding(for: .openLibrary) == HotkeyManager.Action.openLibrary.defaultBinding,
               "reset restores one default")
        expect(HotkeyManager(defaults: hotkeyDefaults).binding(for: .openLibrary)
                == HotkeyManager.Action.openLibrary.defaultBinding,
               "reset persists")

        let secondBinding = HotkeyManager.KeyBinding(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | optionKey)
        )
        try? reloaded.setBinding(secondBinding, for: .nextWallpaper)
        do {
            try reloaded.setBinding(
                HotkeyManager.Action.nextWallpaper.defaultBinding,
                for: .openLibrary
            )
            expect(false, "another action's default is reserved")
        } catch let error as HotkeyManager.BindingError {
            expect(error == .duplicate(.nextWallpaper),
                   "shadowing another default reports the conflict")
        } catch {
            expect(false, "default shadowing throws a BindingError")
        }

        try? reloaded.setBinding(custom, for: .openLibrary)
        try? reloaded.setBinding(secondBinding, for: .nextWallpaper)
        expect(reloaded.isCustomized(.openLibrary) && reloaded.isCustomized(.nextWallpaper),
               "two actions can be customized")
        reloaded.resetAllBindings()
        expect(!reloaded.isCustomized(.openLibrary) && !reloaded.isCustomized(.nextWallpaper),
               "reset all restores every default")
        expect(HotkeyManager(defaults: hotkeyDefaults).bindings.isEmpty,
               "reset all clears persisted custom bindings")

        let invalidStored: [String: HotkeyManager.KeyBinding] = [
            "openLibrary": HotkeyManager.KeyBinding(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: 0
            ),
            "nextWallpaper": HotkeyManager.KeyBinding(
                keyCode: UInt32(kVK_ANSI_L),
                modifiers: UInt32(controlKey | optionKey)
            ),
        ]
        if let data = try? JSONEncoder().encode(invalidStored) {
            hotkeyDefaults.set(data, forKey: HotkeyManager.bindingsKey)
            let sanitized = HotkeyManager(defaults: hotkeyDefaults)
            expect(sanitized.bindings.isEmpty,
                   "invalid or default-shadowing stored bindings are dropped")
        }

        var received: [HotkeyManager.Action] = []
        hotkeys.onAction = { received.append($0) }
        hotkeys.dispatch(identifier: HotkeyManager.Action.openLibrary.identifier)
        expect(received == [.openLibrary], "hotkey events dispatch to their action")
        hotkeys.dispatch(identifier: 99)
        expect(received == [.openLibrary], "unknown hotkey events are ignored")
        UserDefaults.standard.removePersistentDomain(forName: hotkeySuite)

        // MARK: Display layout

        print("Display layout")
        guard let videoConfig = videoPack.flatMap(WallpaperConfig.init(pack:)) else {
            expect(false, "fixture pack produces a wallpaper config")
            print("")
            print("FAIL — fixture setup broken")
            return 1
        }

        var layout = DisplayLayout(defaultConfig: videoConfig)
        let mainID: CGDirectDisplayID = 1
        let sideID: CGDirectDisplayID = 2
        let offID: CGDirectDisplayID = 3

        expect(layout.config(for: mainID)?.title == "Aurora Drift", "default applies to unassigned display")
        var pinnedConfig = videoConfig
        pinnedConfig.title = "Pinned Wallpaper"
        layout.pin(pinnedConfig, for: sideID)
        expect(layout.config(for: sideID)?.title == "Pinned Wallpaper", "pin overrides default per display")
        expect(layout.config(for: mainID)?.title == "Aurora Drift", "other displays keep the default")
        expect(layout.hasPins, "layout reports overrides")

        layout.disable(offID)
        expect(layout.config(for: offID) == nil, "disabled display shows nothing")
        expect(layout.isDisabled(offID), "layout reports a disabled display")
        expect(!layout.isDisabled(mainID), "other displays stay enabled")
        layout.enable(offID)
        expect(layout.config(for: offID)?.title == "Aurora Drift", "re-enabled display returns to default")

        layout.unpin(sideID)
        expect(layout.config(for: sideID)?.title == "Aurora Drift", "unpinned display follows the default")

        // Next Wallpaper has to change what the display is actually showing,
        // even when a pin is overriding the default.
        var advance = DisplayLayout(defaultConfig: videoConfig)
        advance.pin(pinnedConfig, for: sideID)
        var nextConfig = videoConfig
        nextConfig.title = "Next Wallpaper"
        advance.assign(nextConfig, for: sideID)
        expect(advance.config(for: sideID)?.title == "Next Wallpaper",
               "a pinned display advances in place")
        expect(advance.defaultConfig?.title == "Aurora Drift",
               "advancing a pinned display keeps the default")
        expect(advance.config(for: mainID)?.title == "Aurora Drift",
               "other displays keep following the default")
        advance.assign(nextConfig, for: mainID)
        expect(advance.config(for: mainID)?.title == "Next Wallpaper",
               "advancing an unpinned display updates the default")
        expect(advance.defaultConfig?.title == "Next Wallpaper",
               "the default follows an unpinned display")
        var laterConfig = videoConfig
        laterConfig.title = "Later Wallpaper"
        advance.assign(laterConfig, for: mainID)
        expect(advance.config(for: sideID)?.title == "Next Wallpaper",
               "a later default change does not overwrite the pin")
        expect(advance.config(for: sideID) != nil, "the pinned display still has a wallpaper")

        // Next Wallpaper never re-enables a display the user turned off.
        var offLayout = DisplayLayout(defaultConfig: videoConfig)
        offLayout.disable(offID)
        offLayout.assign(nextConfig, for: offID)
        expect(offLayout.isDisabled(offID), "advancing a disabled display leaves it off")

        // Persistence round-trip, including the JSON key representation.
        let layoutStore = WallpaperStore(defaults: defaults)
        var savedLayout = DisplayLayout(defaultConfig: videoConfig)
        savedLayout.pin(pinnedConfig, for: sideID)
        savedLayout.disable(offID)
        layoutStore.save(savedLayout)
        let restored = layoutStore.load()
        expect(restored == savedLayout, "layout round-trips through UserDefaults")
        expect(restored?.config(for: sideID)?.title == "Pinned Wallpaper", "restored pin still applies")
        expect(restored?.config(for: offID) == nil, "restored off display stays off")

        // v1 migration: an older build stored a bare WallpaperConfig.
        if let legacyData = try? JSONEncoder().encode(videoConfig) {
            defaults.set(legacyData, forKey: "tangent.activeWallpaper")
            let migrated = layoutStore.load()
            expect(migrated?.defaultConfig?.title == "Aurora Drift", "v1 single-wallpaper blob migrates to a layout")
            expect(migrated?.config(for: mainID) != nil, "migrated layout still resolves a display")
        } else {
            expect(false, "legacy config encodes")
        }

        layoutStore.clear()
        expect(layoutStore.load() == nil, "clear removes the saved layout")
        expect(!DisplayLayout().hasPlayableConfig, "empty layout has nothing to play")

        // MARK: Wallpaper properties

        print("Wallpaper properties")
        let webRoot = fixturesRoot.appendingPathComponent("library/landing-web")
        let propertyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tangent-properties-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: propertyDirectory) }
        let properties = PropertyStore(baseDirectory: propertyDirectory)

        func sliderValue(_ controls: [PropertyControl], _ name: String) -> Double? {
            guard case .slider(_, _, _, _, let value)? =
                controls.first(where: { $0.name == name })?.spec
            else { return nil }
            return value
        }

        expect(!properties.hasCustomisation(forRoot: webRoot), "no customised copy by default")
        expect(sliderValue(properties.controls(forRoot: webRoot), "speed") == 1.5,
               "defaults come from the pack file")

        expect(properties.setValue(.number(3.5), for: "speed", root: webRoot),
               "setValue writes a slider value")
        expect(properties.hasCustomisation(forRoot: webRoot), "customised copy exists after write")
        expect(sliderValue(properties.controls(forRoot: webRoot), "speed") == 3.5,
               "customised value is read back")

        let copyJSON = try? JSONValue.load(from: properties.copyURL(forRoot: webRoot))
        expect(copyJSON?.value(forKey: "speed")?.value(forKey: "min")?.doubleValue == 0,
               "copy preserves slider min")
        expect(copyJSON?.value(forKey: "speed")?.value(forKey: "max")?.doubleValue == 5,
               "copy preserves slider max")
        expect(copyJSON?.value(forKey: "caption")?.value(forKey: "value")?.stringValue == "Hello",
               "copy preserves untouched controls")
        expect(copyJSON?.value(forKey: "note")?.value(forKey: "type")?.stringValue == "label",
               "copy preserves labels")

        let originalJSON = try? JSONValue.load(
            from: webRoot.appendingPathComponent(PackFormat.propertiesFile)
        )
        expect(originalJSON?.value(forKey: "speed")?.value(forKey: "value")?.doubleValue == 1.5,
               "original pack file is never modified")

        expect(properties.setValue(.bool(false), for: "flip", root: webRoot),
               "second value writes into the same copy")
        if case .checkbox(_, let flip)? =
            properties.controls(forRoot: webRoot).first(where: { $0.name == "flip" })?.spec {
            expect(flip == false, "updated checkbox survives the rewrite")
        } else {
            expect(false, "checkbox parses after rewrite")
        }

        expect(!properties.setValue(.string("nope"), for: "noSuchControl", root: webRoot),
               "unknown control names are rejected")

        properties.reset(root: webRoot)
        expect(!properties.hasCustomisation(forRoot: webRoot), "reset removes the customised copy")
        expect(sliderValue(properties.controls(forRoot: webRoot), "speed") == 1.5,
               "reset restores pack defaults")

        // Bridge semantics for interaction (not load).
        let controlsForInteraction = PackProperties.load(folder: webRoot)
        func interaction(_ name: String) -> JSONValue? {
            controlsForInteraction.first { $0.name == name }?.interactionValue(root: webRoot)
        }
        expect(interaction("speed") == .number(1.5), "slider interaction sends a number")
        expect(interaction("mode") == .number(1), "dropdown interaction sends an index")
        expect(interaction("flip") == .bool(true), "checkbox interaction sends a bool")
        expect(interaction("tint") == .string("#112233"), "colour interaction sends a string")
        expect(interaction("image") == .string("present.jpg"), "existing folder choice sends its name")
        expect(interaction("missingImage") == .null, "missing folder choice sends null")
        expect(interaction("apply") == .bool(true), "button interaction sends true, not its value")
        expect(interaction("note") == nil, "labels send nothing")

        // Folder dropdown options honour the wildcard filter.
        let imagesFolder = webRoot.appendingPathComponent("images")
        expect(PackProperties.folderOptions(folder: imagesFolder, filter: "*.jpg|*.png")
                == ["present.jpg"], "folder filter lists matching files")
        expect(PackProperties.folderOptions(folder: imagesFolder, filter: "*.png").isEmpty,
               "folder filter excludes non-matching files")
        expect(PackProperties.folderOptions(folder: imagesFolder, filter: "")
                .contains("present.jpg"), "empty folder filter lists everything")

        // Colour conversion used by the panel.
        expect(NSColor(hexColor: "#112233")?.hexColor == "#112233", "hex colour round-trips")
        expect(NSColor(hexColor: "#abc")?.hexColor == "#AABBCC", "short hex expands")
        expect(NSColor(hexColor: "not-a-colour") == nil, "invalid hex is rejected")

        // MARK: Ko-fi support

        print("Ko-fi support")
        expect(KoFi.pageURL == TangentLinks.support,
               "support button and support window share one URL")
        expect(KoFi.pageURL.absoluteString == "https://ko-fi.com/anuragcodes",
               "support URL points at the creator's Ko-fi page")
        expect(KoFi.pageURL.host == "ko-fi.com", "support URL uses the ko-fi.com host")
        expect(Theme.koFi != Theme.accent, "Ko-fi button keeps its own brand colour")

        // MARK: Summary

        print("")
        if failures == 0 {
            print("PASS — \(checks) checks")
            return 0
        } else {
            print("FAIL — \(failures) of \(checks) checks failed")
            return 1
        }
    }
}
