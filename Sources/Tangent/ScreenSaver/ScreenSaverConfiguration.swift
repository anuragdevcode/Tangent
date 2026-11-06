import CoreGraphics
import Foundation

/// The hand-off between the app and the screen saver plugin.
///
/// The app owns the layout; the plugin only reads this snapshot. The layout is
/// stored whole so a pinned or disabled display behaves in the screen saver
/// exactly as it does on the desktop.
struct ScreenSaverConfiguration: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var updatedAt: Date
    var layout: DisplayLayout
    /// Where the plugin can find the app's bundled libmpv, when one exists.
    /// AVFoundation-only wallpapers ignore it.
    var libmpvPath: String?

    init(
        layout: DisplayLayout,
        libmpvPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.updatedAt = updatedAt
        self.layout = layout
        self.libmpvPath = libmpvPath
    }

    /// The wallpaper this display should draw, or nil when it is switched off,
    /// has nothing assigned, or the file has since been removed.
    func wallpaper(forDisplayID displayID: CGDirectDisplayID) -> WallpaperConfig? {
        guard let config = layout.config(for: displayID), config.exists else { return nil }
        return config
    }
}

/// Fixed on-disk locations shared by the app and the plugin.
///
/// The screen saver runs inside a sandbox whose container is not the user's
/// home. It derives the real home from its own bundle path
/// (`~/Library/Screen Savers/Tangent.saver`) and reads the config through the
/// read-only filesystem exception macOS grants legacy screen savers.
struct ScreenSaverStorage {
    static let bundleName = "Tangent.saver"
    static let configurationFolder = "ScreenSaver"
    static let configurationFile = "config.json"

    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    var supportDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Tangent", isDirectory: true)
            .appendingPathComponent(Self.configurationFolder, isDirectory: true)
    }

    var configurationURL: URL {
        supportDirectory.appendingPathComponent(Self.configurationFile)
    }

    var screenSaversDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Screen Savers", isDirectory: true)
    }

    var installedBundleURL: URL {
        screenSaversDirectory.appendingPathComponent(Self.bundleName, isDirectory: true)
    }

    func load() -> ScreenSaverConfiguration? {
        guard let data = try? Data(contentsOf: configurationURL) else { return nil }
        return try? JSONDecoder().decode(ScreenSaverConfiguration.self, from: data)
    }

    func save(_ configuration: ScreenSaverConfiguration) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
    }

    func removeInstalledBundle() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: installedBundleURL.path) else { return }
        try fileManager.removeItem(at: installedBundleURL)
    }

    /// Copies the build's bundled saver into `~/Library/Screen Savers` and
    /// writes the configuration next to it. A failed config write removes the
    /// half-installed bundle so the toggle is never left lying.
    func install(from source: URL, configuration: ScreenSaverConfiguration) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: screenSaversDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: installedBundleURL)
        try fileManager.copyItem(at: source, to: installedBundleURL)
        do {
            try save(configuration)
        } catch {
            try? fileManager.removeItem(at: installedBundleURL)
            throw error
        }
    }

    /// Recovers the user's home from a legacy screen saver's bundle path.
    static func homeDirectory(forSaverBundle bundleURL: URL) -> URL? {
        let screenSavers = bundleURL.deletingLastPathComponent()
        guard screenSavers.lastPathComponent == "Screen Savers" else { return nil }
        let library = screenSavers.deletingLastPathComponent()
        guard library.lastPathComponent == "Library" else { return nil }
        return library.deletingLastPathComponent()
    }
}
