import AppKit

// MARK: - Links

/// The few destinations the interface links to. Kept together so they can be
/// changed without hunting through views. GitHub destinations all come from
/// `GitHubRepo`, the single source of truth for the official project.
enum TangentLinks {
    static let repository = GitHubRepo.repository
    static let issues = GitHubRepo.issues
    static let discussions = GitHubRepo.discussions
    static let releases = GitHubRepo.releases
    static let license = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    static let support = URL(string: "https://ko-fi.com/anuragcodes")!
}

// MARK: - Navigation

/// Top-level destinations in the main window.
enum LibrarySection: Int, CaseIterable {
    case all
    case favorites
    case video
    case web
    case images
    case displays
    case automation
    case about

    var title: String {
        switch self {
        case .all: return "All Wallpapers"
        case .favorites: return "Favorites"
        case .video: return "Video"
        case .web: return "Web"
        case .images: return "Images"
        case .displays: return "Displays"
        case .automation: return "Automation"
        case .about: return "About Tangent"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "star"
        case .video: return "film"
        case .web: return "globe"
        case .images: return "photo"
        case .displays: return "display.2"
        case .automation: return "bolt.badge.clock"
        case .about: return "info.circle"
        }
    }

    var filter: LibraryFilter? {
        switch self {
        case .video: return .video
        case .web: return .web
        case .images: return .images
        default: return nil
        }
    }

    var isLibrary: Bool {
        switch self {
        case .all, .favorites, .video, .web, .images: return true
        default: return false
        }
    }

    /// ⌘1 and ⌘2 jump to the two primary destinations.
    var keyEquivalent: String? {
        switch self {
        case .all: return "1"
        case .displays: return "2"
        default: return nil
        }
    }

    static func section(for filter: LibraryFilter) -> LibrarySection {
        switch filter {
        case .video: return .video
        case .web: return .web
        case .images: return .images
        case .unsupported: return .all
        case .all: return .all
        }
    }
}

// MARK: - Snapshot

struct DisplaySummary {
    let id: CGDirectDisplayID
    let label: String
    let isMain: Bool
    let config: WallpaperConfig?
    let isPinned: Bool
    let isDisabled: Bool

    var state: String {
        if isDisabled { return "Off" }
        return config?.title ?? "No wallpaper"
    }
}

/// A cheap, read-only view of engine and app state for the interface.
struct AppSnapshot {
    var isPaused = false
    var pauseReasons: Set<PauseReason> = []
    var isMuted = true
    var defaultConfig: WallpaperConfig?
    /// The library pack behind the default wallpaper, when it is in the library.
    var currentPack: Pack?
    var displays: [DisplaySummary] = []
    var policy = PlaybackMonitor.Policy()
    var packCount = 0
    var hiddenCount = 0
    var favorites: Set<String> = []
    var hotkeysEnabled = false
    var hotkeyStatus = ""
    var statusDescription = "No wallpaper set"

    /// Finder desktop icons, mirrored from `DesktopIcons`. The state is read
    /// from Finder's own preference, not kept separately.
    var desktopIconsState: DesktopIcons.State = .visible
    var desktopIconsBusy = false

    /// GitHub release state, mirrored from `UpdateChecker` so every surface
    /// renders the same answer.
    var updateState: UpdateState = .idle
    var lastUpdateCheck: Date?

    var activeConfigs: [(screen: NSScreen, config: WallpaperConfig)] = []

    var isLive: Bool { defaultConfig != nil && !isPaused }

    var pauseDescription: String? {
        guard isPaused, !pauseReasons.isEmpty else { return nil }
        let ordered: [PauseReason] = [.user, .fullscreen, .battery, .lock]
        let reasons = ordered.filter { pauseReasons.contains($0) }.map { reason -> String in
            switch reason {
            case .user: return "paused manually"
            case .fullscreen: return "a fullscreen app is in front"
            case .battery: return "running on battery power"
            case .lock: return "the screen is locked"
            }
        }
        return "Rendering paused — " + reasons.joined(separator: ", ") + "."
    }
}

// MARK: - Actions

/// Everything the interface can ask the app shell to do. Passing closures keeps
/// the windows free of direct engine or AppKit-global dependencies.
struct AppActions {
    var snapshot: () -> AppSnapshot = { AppSnapshot() }

    // Library
    var apply: (Pack) -> Void = { _ in }
    var applyToAllScreens: (Pack) -> Void = { _ in }
    var setForThisScreen: (Pack) -> Void = { _ in }
    var reveal: (Pack) -> Void = { _ in }
    var duplicate: (Pack) -> Void = { _ in }
    var removeFromLibrary: (Pack) -> Void = { _ in }
    var addWallpaper: () -> Void = {}
    var scanFolder: () -> Void = {}
    var revealLibraryFolder: () -> Void = {}
    var restoreHidden: () -> Void = {}
    var openLibrary: () -> Void = {}
    var openLibrarySection: (LibrarySection) -> Void = { _ in }

    // Playback
    var togglePause: () -> Void = {}
    var nextWallpaper: () -> Void = {}
    var stop: () -> Void = {}
    var setMuted: (Bool) -> Void = { _ in }
    var setPolicy: (PlaybackMonitor.Policy) -> Void = { _ in }
    var setHotkeysEnabled: (Bool) -> Void = { _ in }
    var setDesktopIconsHidden: (Bool) -> Void = { _ in }
    var refreshDesktopIcons: () -> Void = {}

    // Displays
    var useDefaultForDisplay: (CGDirectDisplayID) -> Void = { _ in }
    var pinCurrentToDisplay: (CGDirectDisplayID) -> Void = { _ in }
    var turnOffDisplay: (CGDirectDisplayID) -> Void = { _ in }
    var resetDisplayOverrides: () -> Void = {}

    // Windows
    var openSettings: () -> Void = {}
    var openAbout: () -> Void = {}
    var openProperties: (Pack?) -> Void = { _ in }
    var quit: () -> Void = {}

    // Updates and community
    var checkForUpdates: () -> Void = {}
    var downloadUpdate: () -> Void = {}
    var reportBug: () -> Void = {}
    var copyDiagnostics: () -> Void = {}
    var shareFeedback: () -> Void = {}
    var openRepository: () -> Void = {}
    var openReleaseNotes: () -> Void = {}

    static let preview = AppActions()
}

// MARK: - Formatting

enum Format {

    static func count(_ value: Int, singular: String, plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : plural ?? singular + "s")"
    }

    static func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = bytes >= 1_000_000 ? [.useMB, .useGB] : [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    /// Size of a pack folder, or of the bare file behind a synthetic pack.
    static func size(of pack: Pack) -> String {
        let url = pack.libraryEntry
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "—"
        }

        if !isDirectory.boolValue {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return byteCount(Int64(size))
        }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return "—" }

        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return byteCount(total)
    }

    static func relativePath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func version() -> String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "Unknown"
        #endif
    }

    static var libmpv: String {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/libmpv.2.dylib")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return "Bundled"
        }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib") {
            return "Homebrew"
        }
        return "Not installed"
    }
}

// MARK: - Pack helpers

extension Pack {
    /// The desktop currently shows this pack's entry point.
    func isShowing(in snapshot: AppSnapshot) -> Bool {
        guard let entry = entryURL?.standardizedFileURL.path else { return false }
        return snapshot.activeConfigs.contains {
            $0.config.entryURL.standardizedFileURL.path == entry
        }
    }

    var typeTint: NSColor {
        switch info.type {
        case .video: return .systemBlue
        case .web, .webaudio, .url: return .systemPurple
        case .gif, .picture: return .systemTeal
        default: return .systemOrange
        }
    }
}
