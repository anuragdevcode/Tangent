import CryptoKit
import Foundation

/// Per-wallpaper control values, stored as an edited **copy** of the pack's
/// control file.
///
/// The copy lives in a per-pack container under Application Support and is
/// edited there. The original pack is never modified (so library folders stay
/// pristine and updates are not shadowed) and the customised file is still
/// readable by anyone inspecting the app data.
final class PropertyStore {

    static let shared = PropertyStore()

    /// `~/Library/Application Support/Tangent/Properties`
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Tangent/Properties", isDirectory: true)
    }

    private let baseDirectory: URL
    private let fileManager: FileManager

    init(baseDirectory: URL = PropertyStore.defaultDirectory, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    // MARK: - Locations

    func container(forRoot root: URL) -> URL {
        let name = Self.sanitize(root.lastPathComponent)
        let digest = Self.digest(root.standardizedFileURL.path)
        return baseDirectory.appendingPathComponent("\(name)-\(digest)", isDirectory: true)
    }

    func copyURL(forRoot root: URL) -> URL {
        container(forRoot: root).appendingPathComponent(PackFormat.propertiesFile)
    }

    func hasCustomisation(forRoot root: URL) -> Bool {
        fileManager.fileExists(atPath: copyURL(forRoot: root).path)
    }

    // MARK: - Values

    /// Controls for a pack: the customised copy when one exists, otherwise the
    /// pack's own file. A malformed copy falls back to the original rather than
    /// leaving the wallpaper without a control surface.
    func controls(forRoot root: URL) -> [PropertyControl] {
        let copy = copyURL(forRoot: root)
        if let json = try? JSONValue.load(from: copy) {
            let parsed = PackProperties.parse(json)
            if !parsed.isEmpty { return parsed }
        }
        return PackProperties.load(folder: root)
    }

    /// Writes one control's value into the copy, preserving every other field.
    /// Returns false when the pack has no such control (or no properties file).
    @discardableResult
    func setValue(_ value: JSONValue, for name: String, root: URL) -> Bool {
        let original = root.appendingPathComponent(PackFormat.propertiesFile)
        guard var json = try? JSONValue.load(from: original) else { return false }
        if let existing = try? JSONValue.load(from: copyURL(forRoot: root)) {
            json = existing
        }

        guard var object = json.objectValue,
              var body = object[name]?.objectValue,
              body["type"] != nil
        else { return false }

        body["value"] = value
        object[name] = .object(body)

        let copy = copyURL(forRoot: root)
        do {
            try fileManager.createDirectory(
                at: copy.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = JSONValue.object(object).serialized(pretty: true) else { return false }
            try data.write(to: copy, options: .atomic)
            return true
        } catch {
            NSLog("Tangent: could not save property '%@': %@", name, error.localizedDescription)
            return false
        }
    }

    /// Restores the pack's own defaults by deleting the customised copy.
    func reset(root: URL) {
        try? fileManager.removeItem(at: container(forRoot: root))
    }

    // MARK: - Naming

    /// Filesystem-safe folder name derived from the pack folder.
    private static func sanitize(_ name: String) -> String {
        var out = ""
        var lastWasDash = false
        for character in name {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
            if out.count >= 40 { break }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "wallpaper" : trimmed
    }

    /// Short stable digest so two packs with the same folder name never collide.
    private static func digest(_ value: String) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.prefix(5).map { String(format: "%02x", $0) }.joined()
    }
}
