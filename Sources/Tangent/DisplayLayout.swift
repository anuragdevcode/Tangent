import AppKit
import CoreGraphics

/// Stable identity for a display.
///
/// `CGDirectDisplayID` is what macOS uses in `NSScreen.deviceDescription` and is
/// stable for a given port/monitor pairing across launches, so it can be
/// persisted in a layout. `NSScreen` objects themselves are not stable.
enum DisplayIdentity {
    static let numberKey = NSDeviceDescriptionKey("NSScreenNumber")

    static func id(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[numberKey] as? NSNumber)?.uint32Value ?? 0
    }

    static func key(_ id: CGDirectDisplayID) -> String {
        String(id)
    }

    /// Menu label: the system name, marked when it is the main display.
    static func label(for screen: NSScreen) -> String {
        let name = screen.localizedName
        let isMain = screen == NSScreen.main
        return isMain ? "\(name) (Main)" : name
    }
}

/// How wallpapers are spread over the connected displays.
///
/// One default wallpaper, with optional per-display overrides, plus the
/// ability to leave a display without a wallpaper. Everything is keyed by display ID so the
/// arrangement survives restarts and reconnections.
struct DisplayLayout: Codable, Equatable {
    /// Used by every display that has no override.
    var defaultConfig: WallpaperConfig?
    /// Display ID (as string, because JSON objects need string keys) → wallpaper.
    var pins: [String: WallpaperConfig]
    /// Displays the user explicitly turned off.
    var disabled: [String]

    init(
        defaultConfig: WallpaperConfig? = nil,
        pins: [String: WallpaperConfig] = [:],
        disabled: [String] = []
    ) {
        self.defaultConfig = defaultConfig
        self.pins = pins
        self.disabled = disabled
    }

    // Hand-written so a layout written by a previous build (or a v1 single
    // wallpaper blob) still decodes: missing keys mean "none", not an error.
    //
    // The `contains` check matters: without it every JSON object on earth
    // decodes as an empty layout, which would silently swallow legacy data.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.defaultConfig)
            || container.contains(.pins)
            || container.contains(.disabled)
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not a DisplayLayout: no layout keys present."
            ))
        }
        defaultConfig = try container.decodeIfPresent(WallpaperConfig.self, forKey: .defaultConfig)
        pins = try container.decodeIfPresent([String: WallpaperConfig].self, forKey: .pins) ?? [:]
        disabled = try container.decodeIfPresent([String].self, forKey: .disabled) ?? []
    }

    var hasPins: Bool { !pins.isEmpty || !disabled.isEmpty }

    /// Wallpaper this display should show, or nil when it is switched off or
    /// nothing is configured.
    func config(for displayID: CGDirectDisplayID) -> WallpaperConfig? {
        let key = DisplayIdentity.key(displayID)
        if disabled.contains(key) { return nil }
        if let pinned = pins[key] { return pinned }
        return defaultConfig
    }

    /// Configs that would actually be built, for status text and pruning.
    /// Keyed by display ID.
    func resolved(for screens: [NSScreen]) -> [(screen: NSScreen, config: WallpaperConfig)] {
        screens.compactMap { screen in
            guard let config = config(for: DisplayIdentity.id(of: screen)) else { return nil }
            return (screen, config)
        }
    }

    /// True when at least one configured wallpaper still exists on disk, so the
    /// caller can discard a layout whose files were deleted or moved.
    var hasPlayableConfig: Bool {
        if let defaultConfig, defaultConfig.exists { return true }
        return pins.values.contains { $0.exists }
    }

    mutating func pin(_ config: WallpaperConfig, for displayID: CGDirectDisplayID) {
        let key = DisplayIdentity.key(displayID)
        pins[key] = config
        disabled.removeAll { $0 == key }
    }

    mutating func unpin(_ displayID: CGDirectDisplayID) {
        pins.removeValue(forKey: DisplayIdentity.key(displayID))
    }

    /// Replaces one display's wallpaper without disturbing the others. A pinned
    /// display keeps its own slot; an unpinned display still follows the
    /// default. Used by Next Wallpaper, which must change what is actually on
    /// screen even when a pin is overriding the default.
    mutating func assign(_ config: WallpaperConfig, for displayID: CGDirectDisplayID) {
        let key = DisplayIdentity.key(displayID)
        if pins[key] != nil {
            pins[key] = config
        } else {
            defaultConfig = config
        }
    }

    mutating func disable(_ displayID: CGDirectDisplayID) {
        let key = DisplayIdentity.key(displayID)
        pins.removeValue(forKey: key)
        if !disabled.contains(key) { disabled.append(key) }
    }

    mutating func enable(_ displayID: CGDirectDisplayID) {
        disabled.removeAll { $0 == DisplayIdentity.key(displayID) }
    }

    /// Whether the user explicitly turned this display off.
    func isDisabled(_ displayID: CGDirectDisplayID) -> Bool {
        disabled.contains(DisplayIdentity.key(displayID))
    }

    mutating func resetOverrides() {
        pins.removeAll()
        disabled.removeAll()
    }
}
