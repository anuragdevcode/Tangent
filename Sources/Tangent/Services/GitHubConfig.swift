import AppKit

/// Every GitHub destination Tangent talks to, in one place.
///
/// The app only ever contacts this repository. Keeping the owner, name and URL
/// construction here means a rename is one edit instead of a hunt through menus,
/// cards and network code.
enum GitHubRepo {
    static let owner = "anuragdevcode"
    static let name = "Tangent"

    static let repository = URL(string: "https://github.com/\(owner)/\(name)")!
    static let releases = URL(string: "https://github.com/\(owner)/\(name)/releases")!
    static let issues = URL(string: "https://github.com/\(owner)/\(name)/issues")!
    static let newIssue = URL(string: "https://github.com/\(owner)/\(name)/issues/new")!
    static let discussions = URL(string: "https://github.com/\(owner)/\(name)/discussions")!
    static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest"
    )!

    /// The issue form Tangent links to. The form itself lives in
    /// `.github/ISSUE_TEMPLATE/bug_report.yml`.
    static let bugReportTemplate = "bug_report.yml"

    /// Issue form with the template selected. Additional query items (title)
    /// are added by `FeedbackManager`.
    static let bugReportForm: URL = {
        var components = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "template", value: bugReportTemplate)]
        return components?.url ?? newIssue
    }()

    /// Canonical repository slug used in releases and download assets.
    static var slug: String { "\(owner)/\(name)" }
}

/// The only way the app opens a browser.
///
/// External URLs come from GitHub's API, so they are checked before they are
/// handed to `NSWorkspace`: HTTPS only, with a host. Nothing is downloaded,
/// mounted or executed.
enum ExternalLink {

    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard isSafe(url) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func isSafe(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// A validated HTTPS URL from an API string, or nil when it is missing,
    /// malformed, or uses another scheme.
    static func https(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw), isSafe(url) else {
            return nil
        }
        return url
    }
}
