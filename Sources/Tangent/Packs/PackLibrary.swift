import Foundation

/// Discovers wallpaper packs on disk.
///
/// Each pack is a folder containing a metadata file. Bare files may also be
/// referenced directly, which covers user-opened wallpapers (`IsAbsolutePath`
/// entries).
final class PackLibrary {

    private let defaults: UserDefaults
    private let rootsKey = "tangent.library.roots"
    private let entriesKey = "tangent.library.entries"
    private let hiddenKey = "tangent.library.hidden"

    private(set) var roots: [URL]
    private(set) var entries: [URL]
    /// Packs removed through the interface. Hiding rather than deleting keeps
    /// the promise that Tangent never removes files from disk.
    private(set) var hidden: Set<String>

    /// `~/Library/Application Support/Tangent/Library`
    static var defaultRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Tangent/Library", isDirectory: true)
    }

    /// `fallbackRoot` is only used when the store has no roots yet. Tests pass a
    /// scratch directory so they never scan the user's real library.
    init(defaults: UserDefaults = .standard, fallbackRoot: URL = PackLibrary.defaultRoot) {
        self.defaults = defaults
        let rootPaths = defaults.stringArray(forKey: rootsKey) ?? []
        let entryPaths = defaults.stringArray(forKey: entriesKey) ?? []
        self.roots = rootPaths.map { URL(fileURLWithPath: $0) }
        self.entries = entryPaths.map { URL(fileURLWithPath: $0) }
        self.hidden = Set(defaults.stringArray(forKey: hiddenKey) ?? [])

        if roots.isEmpty {
            roots = [fallbackRoot]
            persist()
        }
        try? FileManager.default.createDirectory(
            at: fallbackRoot,
            withIntermediateDirectories: true
        )
    }

    func addRoot(_ url: URL) {
        guard !roots.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        roots.append(url)
        persist()
    }

    func addEntry(_ url: URL) {
        guard !entries.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        entries.append(url)
        persist()
    }

    func removeEntry(_ url: URL) {
        entries.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persist()
    }

    func hide(_ pack: Pack) {
        hidden.insert(pack.id)
        persist()
    }

    func restoreHidden() {
        hidden.removeAll()
        persist()
    }

    func isHidden(_ pack: Pack) -> Bool {
        hidden.contains(pack.id)
    }

    /// Full scan. Deduplicates by resolved entry point so a pack that is both
    /// in the library root and explicitly added appears once. Hidden packs are
    /// left in place on disk and skipped here.
    func scan() -> [Pack] {
        var found: [String: Pack] = [:]

        for root in roots {
            for child in contents(of: root) {
                if let pack = Pack.synthetic(fileURL: child), !hidden.contains(pack.id) {
                    found[pack.id] = pack
                }
            }
        }

        for entry in entries {
            if let pack = Pack.synthetic(fileURL: entry), !hidden.contains(pack.id) {
                found[pack.id] = pack
            }
        }

        return found.values.sorted {
            $0.info.title.localizedCaseInsensitiveCompare($1.info.title) == .orderedAscending
        }
    }

    private func contents(of directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func persist() {
        defaults.set(roots.map(\.path), forKey: rootsKey)
        defaults.set(entries.map(\.path), forKey: entriesKey)
        defaults.set(Array(hidden).sorted(), forKey: hiddenKey)
    }
}
