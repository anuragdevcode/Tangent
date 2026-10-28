import Foundation

/// Persists the active display layout.
///
/// This stores the part that has to survive a restart: which wallpaper is on
/// which display. Older builds wrote a single `WallpaperConfig` under the same key, so
/// `load()` migrates that shape instead of dropping the user's wallpaper.
final class WallpaperStore {
    private let key = "tangent.activeWallpaper"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DisplayLayout? {
        guard let data = defaults.data(forKey: key) else { return nil }

        if let layout = try? JSONDecoder().decode(DisplayLayout.self, from: data) {
            return layout
        }
        // v1 (Phase 1 / early Phase 2) stored a bare config.
        if let legacy = try? JSONDecoder().decode(WallpaperConfig.self, from: data) {
            return DisplayLayout(defaultConfig: legacy)
        }
        return nil
    }

    func save(_ layout: DisplayLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
