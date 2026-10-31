import Foundation

/// The metadata file every wallpaper pack folder carries.
/// Field names and semantics follow the pack format's info schema.
struct PackInfo {
    var title: String
    var type: WallpaperType
    var fileName: String?
    var isAbsolutePath: Bool
    var thumbnail: String?
    var preview: String?
    var author: String?
    var summary: String?
    var license: String?
    var contact: String?
    var tags: [String]
    var version: Int
    var appVersion: String?
    var galleryId: String?

    static func parse(_ json: JSONValue, fallbackTitle: String) -> PackInfo {
        let title = json.value(forKey: "Title")?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let typeRaw = json.value(forKey: "Type")?.stringValue ?? "web"

        var tags: [String] = []
        if let rawTags = json.value(forKey: "Tags")?.arrayValue {
            tags = rawTags.compactMap(\.stringValue)
        }

        return PackInfo(
            title: (title?.isEmpty == false ? title! : fallbackTitle),
            type: WallpaperType(raw: typeRaw),
            fileName: json.value(forKey: "FileName")?.stringValue,
            isAbsolutePath: json.value(forKey: "IsAbsolutePath")?.boolValue ?? false,
            thumbnail: json.value(forKey: "Thumbnail")?.stringValue,
            preview: json.value(forKey: "Preview")?.stringValue,
            author: json.value(forKey: "Author")?.stringValue,
            summary: json.value(forKey: "Desc")?.stringValue,
            license: json.value(forKey: "License")?.stringValue,
            contact: json.value(forKey: "Contact")?.stringValue,
            tags: tags,
            version: json.value(forKey: "Version")?.intValue ?? 0,
            appVersion: json.value(forKey: "AppVersion")?.stringValue,
            galleryId: json.value(forKey: "Id")?.stringValue
        )
    }
}

/// A wallpaper pack on disk: the folder plus its parsed metadata.
struct Pack {
    let folder: URL
    let info: PackInfo
    /// Item to add to the library: the pack folder, or the bare file when this
    /// pack was synthesised from a dragged-in video/image/html file.
    var libraryItem: URL?

    /// `FileName` is relative to the folder unless `IsAbsolutePath` is set, in
    /// which case it is a full path (auto-generated tiles do this).
    var entryURL: URL? {
        guard let fileName = info.fileName, !fileName.isEmpty else {
            // No filename: a web pack's entry point is by convention index.html.
            switch info.type {
            case .web, .webaudio:
                let index = folder.appendingPathComponent("index.html")
                return FileManager.default.fileExists(atPath: index.path) ? index : nil
            default:
                return nil
            }
        }

        if fileName.hasPrefix("http://") || fileName.hasPrefix("https://") {
            return URL(string: fileName)
        }
        if info.isAbsolutePath || fileName.hasPrefix("/") {
            return URL(fileURLWithPath: fileName)
        }
        return folder.appendingPathComponent(fileName)
    }

    var isRemoteEntry: Bool {
        guard let entry = entryURL else { return false }
        return entry.scheme == "http" || entry.scheme == "https"
    }

    /// Thumbnails follow the same relative/absolute rule as `FileName`.
    var thumbnailURL: URL? {
        guard let thumbnail = info.thumbnail, !thumbnail.isEmpty else { return nil }
        if info.isAbsolutePath || thumbnail.hasPrefix("/") {
            return URL(fileURLWithPath: thumbnail)
        }
        return folder.appendingPathComponent(thumbnail)
    }

    var previewURL: URL? {
        guard let preview = info.preview, !preview.isEmpty else { return nil }
        if info.isAbsolutePath || preview.hasPrefix("/") {
            return URL(fileURLWithPath: preview)
        }
        return folder.appendingPathComponent(preview)
    }

    var propertiesURL: URL {
        folder.appendingPathComponent(PackFormat.propertiesFile)
    }

    /// Stable identity for selection, thumbnails, favorites and hiding.
    ///
    /// A bare file would otherwise share its parent folder's path with every
    /// other file in that folder, so two videos side by side would collapse
    /// into one entry. Synthetic packs therefore identify by the file itself.
    var id: String { libraryEntry.standardizedFileURL.path }

    /// Folder for a real pack, the file itself for synthetic ones.
    var libraryEntry: URL { libraryItem ?? folder }

    /// Human-readable reason a pack cannot run here, or nil if it can.
    var unsupportedReason: String? {
        if let reason = info.type.unsupportedReason { return reason }
        guard let entry = entryURL else {
            return "\(PackFormat.infoFile) does not point at a playable file (FileName is missing or the entry point is absent)."
        }
        if !isRemoteEntry, !FileManager.default.fileExists(atPath: entry.path) {
            return "Entry point is missing: \(entry.lastPathComponent)"
        }
        return nil
    }

    static func load(folder: URL) throws -> Pack? {
        let infoURL = folder.appendingPathComponent(PackFormat.infoFile)
        guard FileManager.default.fileExists(atPath: infoURL.path) else { return nil }
        let json = try JSONValue.load(from: infoURL)
        let info = PackInfo.parse(json, fallbackTitle: folder.lastPathComponent)
        return Pack(folder: folder, info: info)
    }

    /// Wraps a bare file (user dragged in a video or an index.html) as a pack
    /// with synthetic metadata, so everything downstream has one shape.
    static func synthetic(fileURL: URL) -> Pack? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            if let pack = try? load(folder: fileURL) { return pack }
            let index = fileURL.appendingPathComponent("index.html")
            guard FileManager.default.fileExists(atPath: index.path) else { return nil }
            let info = PackInfo(
                title: fileURL.lastPathComponent, type: .web,
                fileName: "index.html", isAbsolutePath: false,
                thumbnail: nil, preview: nil, author: nil, summary: nil,
                license: nil, contact: nil, tags: [], version: 0,
                appVersion: nil, galleryId: nil
            )
            return Pack(folder: fileURL, info: info)
        }

        let ext = fileURL.pathExtension.lowercased()
        let type: WallpaperType
        switch ext {
        case "mp4", "mov", "m4v", "mpg", "mpeg", "avi", "webm", "mkv", "ogv", "flv":
            type = .video
        case "gif": type = .gif
        case "png", "jpg", "jpeg", "heic", "tiff", "bmp", "webp": type = .picture
        case "html", "htm": type = .web
        default: return nil
        }

        let info = PackInfo(
            title: fileURL.deletingPathExtension().lastPathComponent, type: type,
            fileName: fileURL.path, isAbsolutePath: true,
            thumbnail: nil, preview: nil, author: nil, summary: nil,
            license: nil, contact: nil, tags: [], version: 0,
            appVersion: nil, galleryId: nil
        )
        return Pack(
            folder: fileURL.deletingLastPathComponent(),
            info: info,
            libraryItem: fileURL
        )
    }
}
