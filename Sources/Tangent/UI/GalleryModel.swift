import Foundation

/// Filter shown in the gallery's type popup.
enum LibraryFilter: String, CaseIterable {
    case all
    case video
    case web
    case images
    case unsupported

    var title: String {
        switch self {
        case .all: return "All Wallpapers"
        case .video: return "Video"
        case .web: return "Web"
        case .images: return "GIF & Image"
        case .unsupported: return "Unsupported"
        }
    }

    func matches(_ pack: Pack) -> Bool {
        switch self {
        case .all:
            return true
        case .video:
            return pack.info.type == .video
        case .web:
            return [.web, .webaudio, .url].contains(pack.info.type)
        case .images:
            return [.gif, .picture].contains(pack.info.type)
        case .unsupported:
            return pack.unsupportedReason != nil
        }
    }
}

/// Search + filter state for the gallery. Kept separate from AppKit so the
/// behaviour can be unit tested without a window.
struct LibraryQuery: Equatable {
    var search: String = ""
    var filter: LibraryFilter = .all

    func apply(to packs: [Pack]) -> [Pack] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return packs.filter { pack in
            guard filter.matches(pack) else { return false }
            guard !needle.isEmpty else { return true }
            return Self.haystack(for: pack).localizedCaseInsensitiveContains(needle)
        }
    }

    /// Everything a user might type to find a wallpaper: visible metadata plus
    /// the folder name, which is often the only meaningful text for bare files.
    static func haystack(for pack: Pack) -> String {
        [
            pack.info.title,
            pack.info.author ?? "",
            pack.info.summary ?? "",
            pack.info.type.displayName,
            pack.info.tags.joined(separator: " "),
            pack.folder.lastPathComponent,
        ].joined(separator: " ")
    }
}

/// Next/previous wallpaper in the library, skipping packs that cannot run.
enum WallpaperCycler {
    static func next(
        after current: Pack?,
        in packs: [Pack],
        forward: Bool = true
    ) -> Pack? {
        let playable = packs.filter { $0.unsupportedReason == nil }
        guard !playable.isEmpty else { return nil }

        guard let current,
              let index = playable.firstIndex(where: { $0.id == current.id })
        else {
            return forward ? playable.first : playable.last
        }

        let offset = forward ? 1 : playable.count - 1
        return playable[(index + offset) % playable.count]
    }
}
