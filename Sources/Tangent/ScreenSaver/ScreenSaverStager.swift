import Darwin
import Foundation

/// Copies the active wallpaper somewhere the screen saver can actually read.
///
/// The legacy screen saver host is sandboxed. Its sandbox profile allows reads
/// from `/`, but TCC still protects Desktop, Documents, Downloads and iCloud
/// Drive. A wallpaper chosen from one of those folders plays on the desktop and
/// is then denied to the saver, which leaves an empty layer and reveals the
/// desktop picture. Staging under Application Support sidesteps TCC without
/// asking for Full Disk Access or moving the user's files.
///
/// The copy deliberately keeps the app's own layout untouched. Only the
/// snapshot written for the plugin points at the staged paths.
final class ScreenSaverStager {
    private let storage: ScreenSaverStorage
    private let fileManager: FileManager

    init(storage: ScreenSaverStorage, fileManager: FileManager = .default) {
        self.storage = storage
        self.fileManager = fileManager
    }

    private struct Staged {
        let entry: URL
        let root: URL?
    }

    /// A configuration whose local paths can be opened by the saver.
    func prepare(_ configuration: ScreenSaverConfiguration) -> ScreenSaverConfiguration {
        var stagedBySource: [String: Staged] = [:]
        var keptMedia: Set<String> = []
        var keptMPV: Set<String> = []

        func stage(_ config: WallpaperConfig) -> WallpaperConfig {
            guard !config.isRemote else { return config }
            let source = config.entryURL
            guard fileManager.fileExists(atPath: source.path) else { return config }
            // Already staged: keep the existing copy instead of nesting a
            // second generation under a new path.
            if let folder = stagedFolder(containing: source, in: mediaDirectory) {
                keptMedia.insert(folder)
                return config
            }
            let staged: Staged
            if let cached = stagedBySource[source.path] {
                staged = cached
            } else if needsPackCopy(config), let root = config.root {
                guard let pack = stagePack(root: root, entry: source, keep: &keptMedia) else {
                    return config
                }
                staged = pack
            } else {
                guard let file = stageFile(source, keep: &keptMedia) else { return config }
                staged = Staged(
                    entry: file,
                    root: (config.type == .web || config.type == .webaudio)
                        ? file.deletingLastPathComponent()
                        : nil
                )
            }
            stagedBySource[source.path] = staged

            var copy = config
            copy.entry = staged.entry.path
            copy.rootFolder = staged.root?.path
            return copy
        }

        var layout = configuration.layout
        layout.defaultConfig = layout.defaultConfig.map(stage)
        for key in layout.pins.keys {
            layout.pins[key] = layout.pins[key].map(stage)
        }

        prune(mediaDirectory, keeping: keptMedia)

        let libmpv = stageLibmpv(configuration.libmpvPath, keep: &keptMPV)
        prune(mpvDirectory, keeping: keptMPV)

        return ScreenSaverConfiguration(
            layout: layout,
            libmpvPath: libmpv,
            updatedAt: configuration.updatedAt
        )
    }

    // MARK: - Media staging

    private var mediaDirectory: URL {
        storage.supportDirectory.appendingPathComponent("Media", isDirectory: true)
    }

    private func stageFile(_ source: URL, keep: inout Set<String>) -> URL? {
        let fingerprint = "\(stableKey(source.path))-\(fileFingerprint(source))"
        let folder = mediaDirectory.appendingPathComponent(fingerprint, isDirectory: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        keep.insert(fingerprint)
        if fileManager.fileExists(atPath: destination.path),
           fileSize(destination) == fileSize(source) {
            return destination
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try copyFile(source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Copies a web folder so relative assets resolve. Falls back to the entry
    /// file when the folder is not a recognized pack.
    private func stagePack(root: URL, entry: URL, keep: inout Set<String>) -> Staged? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              entry.path.hasPrefix(root.path + "/"),
              root.standardizedFileURL.path != homePath,
              !isProtectedFolder(root) || fileManager.fileExists(
                  atPath: root.appendingPathComponent(PackFormat.infoFile).path
              )
        else {
            guard let file = stageFile(entry, keep: &keep) else { return nil }
            return Staged(entry: file, root: file.deletingLastPathComponent())
        }

        let fingerprint = "\(stableKey(root.path))-\(directoryFingerprint(root))"
        let destination = mediaDirectory.appendingPathComponent(fingerprint, isDirectory: true)
        keep.insert(fingerprint)
        let stagedEntry = destination.appendingPathComponent(
            String(entry.path.dropFirst(root.path.count + 1))
        )
        guard !fileManager.fileExists(atPath: stagedEntry.path) else {
            return Staged(entry: stagedEntry, root: destination)
        }
        do {
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: root, to: destination)
            return Staged(entry: stagedEntry, root: destination)
        } catch {
            return nil
        }
    }

    /// Web packs load relative assets, so a single file is not enough. Copy a
    /// folder when it carries pack metadata or is a dedicated `index.html`
    /// page. A lone `wallpaper.html` in Downloads stays a file copy; copying
    /// the whole Downloads folder because of one HTML file would be a
    /// surprising amount of disk I/O.
    private func needsPackCopy(_ config: WallpaperConfig) -> Bool {
        guard config.type == .web || config.type == .webaudio else { return false }
        guard let root = config.root else { return false }
        if fileManager.fileExists(
            atPath: root.appendingPathComponent(PackFormat.infoFile).path
        ) { return true }
        guard !isProtectedFolder(root) else { return false }
        let entry = config.entryURL
        return entry.lastPathComponent.lowercased() == "index.html"
            && entry.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
    }

    // MARK: - libmpv staging

    private func stageLibmpv(_ path: String?, keep: inout Set<String>) -> String? {
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else { return path }
        if let folder = stagedFolder(containing: url, in: mpvDirectory) {
            keep.insert(folder)
            return path
        }
        // Homebrew and /Applications are readable to the saver. Only a copy of
        // the app that lives in a TCC-protected folder needs its frameworks
        // staged, and libmpv needs every sibling dylib it loads.
        guard isProtectedByTCC(url) else { return path }

        let sourceFolder = url.deletingLastPathComponent()
        let fingerprint = "\(stableKey(sourceFolder.path))-\(directoryFingerprint(sourceFolder))"
        let destination = mpvDirectory.appendingPathComponent(fingerprint, isDirectory: true)
        keep.insert(fingerprint)
        let stagedLibrary = destination.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: stagedLibrary.path) { return stagedLibrary.path }
        do {
            try fileManager.createDirectory(at: mpvDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: sourceFolder, to: destination)
            return stagedLibrary.path
        } catch {
            return path
        }
    }

    private var mpvDirectory: URL {
        storage.supportDirectory.appendingPathComponent("MPV", isDirectory: true)
    }

    // MARK: - Files

    private func copyFile(_ source: URL, to destination: URL) throws {
        // APFS clones make a second copy of a multi-gigabyte wallpaper nearly
        // free. Fall back to a real copy for non-APFS volumes.
        if clonefile(source.path, destination.path, 0) == 0 { return }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func fileFingerprint(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let stamp = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return "\(size)-\(stamp)"
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    private func directoryFingerprint(_ root: URL) -> String {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
        ]
        guard let walker = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return "0" }

        var count = 0
        var bytes = 0
        var latest = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            count += 1
            bytes += values.fileSize ?? 0
            latest = max(latest, Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0))
            if count > 20_000 { break }
        }
        return "\(count)-\(bytes)-\(latest)"
    }

    /// Top-level folder name when `url` already lives in a staging directory.
    private func stagedFolder(containing url: URL, in directory: URL) -> String? {
        let prefix = directory.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return nil }
        return path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
    }

    private func prune(_ directory: URL, keeping names: Set<String>) {        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-300)
        for entry in entries where !names.contains(entry.lastPathComponent) {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            // Keep the previous generation briefly: a running saver may still
            // be reading it while the new config is being written.
            if modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    // MARK: - Identity

    /// FNV-1a: stable across launches, unlike `String.hashValue`.
    private func stableKey(_ path: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    private func isProtectedByTCC(_ url: URL) -> Bool {
        let home = homePath
        let path = url.standardizedFileURL.path
        return ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].contains {
            let folder = home + "/" + $0
            return path == folder || path.hasPrefix(folder + "/")
        }
    }

    private func isProtectedFolder(_ url: URL) -> Bool {
        isProtectedByTCC(url) || url.standardizedFileURL.path == homePath
    }

    private var homePath: String {
        fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
    }
}
