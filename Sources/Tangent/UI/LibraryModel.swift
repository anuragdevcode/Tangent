import AppKit

/// Library state. Plain observable-by-callback model (no SwiftUI, so the build
/// works with Command Line Tools alone).
final class LibraryModel {

    private(set) var packs: [Pack] = []

    /// Search/filter state. Setting it notifies the window so both the grid and
    /// the count update together.
    var query = LibraryQuery() {
        didSet {
            guard oldValue != query else { return }
            onChange?()
        }
    }

    var visiblePacks: [Pack] { query.apply(to: packs) }

    private let library: PackLibrary
    private let defaults: UserDefaults
    private let favoritesKey = "tangent.library.favorites"
    private(set) var favorites: Set<String>

    var onChange: (() -> Void)?
    var onApply: ((Pack) -> Void)?

    var hiddenCount: Int { library.hidden.count }

    init(library: PackLibrary = PackLibrary(), defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
        self.favorites = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        reload()
    }

    func reload() {
        packs = library.scan()
        // Favorites for packs that no longer exist are harmless, but pruning
        // keeps the stored set from growing forever.
        let ids = Set(packs.map(\.id))
        let pruned = favorites.intersection(ids)
        if pruned != favorites {
            favorites = pruned
            persistFavorites()
        }
        onChange?()
    }

    func add(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            let hasInfo = FileManager.default.fileExists(
                atPath: url.appendingPathComponent(PackFormat.infoFile).path
            )
            if hasInfo {
                library.addEntry(url)
            } else {
                library.addRoot(url)
            }
        } else {
            library.addEntry(url)
        }
        reload()
    }

    // MARK: - Favorites

    func isFavorite(_ pack: Pack) -> Bool {
        favorites.contains(pack.id)
    }

    func toggleFavorite(_ pack: Pack) {
        if favorites.contains(pack.id) {
            favorites.remove(pack.id)
        } else {
            favorites.insert(pack.id)
        }
        persistFavorites()
        onChange?()
    }

    private func persistFavorites() {
        defaults.set(Array(favorites).sorted(), forKey: favoritesKey)
    }

    // MARK: - Removing and duplicating

    /// Removes a pack from the library without touching its files.
    func hide(_ pack: Pack) {
        library.hide(pack)
        reload()
    }

    func restoreHidden() {
        library.restoreHidden()
        reload()
    }

    /// Copies a pack into the library folder under a new name. Folders stay
    /// folders; bare files keep their extension. Returns the new pack.
    @discardableResult
    func duplicate(_ pack: Pack) -> Pack? {
        let fileManager = FileManager.default
        let source = pack.libraryEntry
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            return nil
        }

        let base = sanitized(pack.info.title)
        let ext = isDirectory.boolValue ? "" : source.pathExtension
        let root = PackLibrary.defaultRoot
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var counter = 1
        var destination: URL
        repeat {
            let suffix = counter == 1 ? " Copy" : " Copy \(counter)"
            let name = base + suffix + (ext.isEmpty ? "" : "." + ext)
            destination = root.appendingPathComponent(name)
            counter += 1
        } while fileManager.fileExists(atPath: destination.path)

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            return nil
        }

        library.addEntry(destination)
        reload()
        return packs.first { $0.id == destination.standardizedFileURL.path }
    }

    private func sanitized(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Wallpaper" : cleaned
    }

    // MARK: - Folders

    func revealLibraryFolder() {
        try? FileManager.default.createDirectory(
            at: PackLibrary.defaultRoot,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([PackLibrary.defaultRoot])
    }
}
