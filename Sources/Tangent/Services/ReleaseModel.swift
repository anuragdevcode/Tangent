import Foundation

// MARK: - Release model

/// The subset of GitHub's release payload Tangent needs.
///
/// Decoding is forgiving: GitHub omits `name` on untitled releases and some
/// releases have no assets at all. Those cases are data, not errors.
struct GitHubRelease: Codable, Equatable, Sendable {

    struct Asset: Codable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: String
        let contentType: String?
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case contentType = "content_type"
            case size
        }
    }

    let tagName: String
    let name: String?
    let htmlURL: String?
    let publishedAt: String?
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }

    init(
        tagName: String,
        name: String? = nil,
        htmlURL: String? = nil,
        publishedAt: String? = nil,
        prerelease: Bool = false,
        draft: Bool = false,
        assets: [Asset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.draft = draft
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        // A malformed asset should not discard a usable release.
        assets = (try? container.decode([Asset].self, forKey: .assets)) ?? []
    }

    /// The release page, validated.
    var pageURL: URL? { ExternalLink.https(htmlURL) }

    /// DMG attachments, matched without caring about case.
    var diskImages: [Asset] {
        assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
    }

    /// Picks the most appropriate DMG for this Mac:
    /// universal first, then an architecture match, then the only DMG.
    func preferredDMG(for architecture: MacArchitecture) -> Asset? {
        let images = diskImages
        guard !images.isEmpty else { return nil }

        if let universal = images.first(where: { $0.name.lowercased().contains("universal") }) {
            return universal
        }

        let tokens = architecture.assetTokens
        if !tokens.isEmpty,
           let match = images.first(where: { asset in
               let name = asset.name.lowercased()
               return tokens.contains { name.contains($0) }
           }) {
            return match
        }

        // One DMG is unambiguous; several without a recognisable name are not.
        return images.count == 1 ? images[0] : nil
    }

    /// A direct DMG when one can be chosen, otherwise the release page so the
    /// user can pick an asset themselves. Never assumes asset order.
    func downloadURL(for architecture: MacArchitecture) -> URL? {
        if let asset = preferredDMG(for: architecture),
           let url = ExternalLink.https(asset.browserDownloadURL) {
            return url
        }
        return pageURL
    }
}

// MARK: - Architectures

enum MacArchitecture: String, Sendable {
    case arm64
    case x86_64
    case unknown

    static var current: MacArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }

    var displayName: String {
        switch self {
        case .arm64: return "arm64"
        case .x86_64: return "x86_64"
        case .unknown: return "Unknown"
        }
    }

    /// Filename fragments used to match a release asset. Avoid single letters
    /// and bare `m1`/`m2`, which collide with version numbers.
    var assetTokens: [String] {
        switch self {
        case .arm64: return ["arm64", "aarch64", "apple-silicon", "apple_silicon"]
        case .x86_64: return ["x86_64", "x86-64", "intel", "amd64"]
        case .unknown: return []
        }
    }
}

// MARK: - Semantic versions

/// A comparable semantic version. Tags may arrive as `v1.2.3`; build metadata
/// (`+abc`) is ignored for precedence, exactly as the spec requires.
struct ReleaseVersion: Equatable, Comparable, CustomStringConvertible, Sendable {

    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses `1.2.3`, `v1.2.3`, `1.2` and `1.2.3-beta.2`. Returns nil for
    /// anything else rather than guessing, so a bad tag is never advertised.
    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        // Build metadata does not participate in ordering.
        if let plus = text.firstIndex(of: "+") {
            text = String(text[..<plus])
        }
        guard !text.isEmpty else { return nil }

        var identifiers: [String] = []
        if let dash = text.firstIndex(of: "-") {
            let suffix = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
            guard !suffix.isEmpty else { return nil }
            identifiers = suffix
                .split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard !identifiers.contains(where: \.isEmpty) else { return nil }
            for identifier in identifiers {
                let valid = identifier.allSatisfy { character in
                    character.isASCII
                        && (character.isLetter || character.isNumber || character == "-")
                }
                guard valid else { return nil }
            }
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part)
            else { return nil }
            numbers.append(value)
        }
        guard numbers.count == parts.count else { return nil }

        major = numbers[0]
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0
        prerelease = identifiers
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return prereleasePrecedes(lhs.prerelease, rhs.prerelease)
    }

    /// Semver precedence 11: a release outranks its prereleases, numeric
    /// identifiers compare numerically, numeric sorts below alphanumeric, and a
    /// longer identifier list wins when all shared identifiers match.
    private static func prereleasePrecedes(_ lhs: [String], _ rhs: [String]) -> Bool {
        if lhs.isEmpty { return false }
        if rhs.isEmpty { return true }

        for (left, right) in zip(lhs, rhs) {
            if left == right { continue }
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            if let leftNumber, let rightNumber {
                if leftNumber != rightNumber { return leftNumber < rightNumber }
                continue
            }
            if leftNumber != nil { return true }
            if rightNumber != nil { return false }
            return left < right
        }
        return lhs.count < rhs.count
    }
}

// MARK: - Update decision

/// A release that is actually newer than the running build, with the safest
/// download destination already resolved.
struct AvailableUpdate: Equatable, Sendable {
    let version: ReleaseVersion
    let tag: String
    let releasePageURL: URL?
    let assetURL: URL?

    /// A DMG when one matches this Mac, otherwise the release page.
    var downloadURL: URL? { assetURL ?? releasePageURL }
    var isDirectDownload: Bool { assetURL != nil }
}

/// What the interface should show after a release lookup.
enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AvailableUpdate)
    case offline
    case rateLimited
    case failed(message: String)

    var update: AvailableUpdate? {
        if case .updateAvailable(let update) = self { return update }
        return nil
    }

    var isChecking: Bool { self == .checking }
}

/// Pure version policy, kept apart from networking so it can be tested with
/// fixed payloads.
enum UpdateDecision {

    /// Decides whether a release should be advertised. Drafts and prereleases
    /// are never offered to a stable build, even if GitHub returns them.
    static func evaluate(
        release: GitHubRelease,
        installed: ReleaseVersion,
        architecture: MacArchitecture = .current
    ) -> UpdateState {
        guard let latest = ReleaseVersion(release.tagName) else {
            return .failed(message: "The latest release tag isn’t a version.")
        }
        guard !release.draft else { return .upToDate }
        if release.prerelease && !installed.isPrerelease {
            return .upToDate
        }
        guard latest > installed else { return .upToDate }

        let asset = ExternalLink.https(
            release.preferredDMG(for: architecture)?.browserDownloadURL
        )
        let page = release.pageURL ?? GitHubRepo.releases
        return .updateAvailable(
            AvailableUpdate(
                version: latest,
                tag: release.tagName,
                releasePageURL: page,
                assetURL: asset
            )
        )
    }
}

/// The 24-hour throttle for automatic checks.
enum UpdateSchedule {
    static let interval: TimeInterval = 24 * 60 * 60

    static func isDue(
        last: Date?,
        now: Date,
        interval: TimeInterval = interval
    ) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last)
        // A clock that moved backwards should not stall checks forever.
        return elapsed >= interval || elapsed < 0
    }
}
