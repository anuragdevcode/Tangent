import Foundation

// MARK: - Lookup result

enum ReleaseLookupResult: Equatable {
    case release(GitHubRelease, etag: String?)
    case notModified
    case noRelease
    case rateLimited
    case offline
    case failed

    /// Maps GitHub's HTTP answer without any UI or persistence involved, so the
    /// edge cases (rate limits, 404, invalid JSON) are unit-testable.
    static func classify(
        statusCode: Int,
        etag: String?,
        rateLimitRemaining: String?,
        data: Data
    ) -> ReleaseLookupResult {
        switch statusCode {
        case 200...299:
            guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                return .failed
            }
            return .release(release, etag: etag)
        case 304:
            return .notModified
        case 403, 429:
            if statusCode == 429 || rateLimitRemaining == "0" {
                return .rateLimited
            }
            return .failed
        case 404:
            return .noRelease
        default:
            return .failed
        }
    }

    /// Network failures are separated from bad responses: offline is a normal
    /// state for a menu-bar app, not an error to shout about.
    static func classify(error: Error) -> ReleaseLookupResult {
        guard let urlError = error as? URLError else { return .failed }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut,
             .internationalRoamingOff,
             .dataNotAllowed:
            return .offline
        default:
            return .failed
        }
    }
}

// MARK: - Networking

/// One conditional GET against the official release endpoint.
struct ReleaseLookup {

    let session: URLSession
    let version: String

    init(session: URLSession = .shared, version: String = UpdateChecker.installedVersion) {
        self.session = session
        self.version = version
    }

    func latest(etag: String?) async -> ReleaseLookupResult {
        var request = URLRequest(url: GitHubRepo.latestReleaseAPI)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tangent/\(version)", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            return ReleaseLookupResult.classify(
                statusCode: http.statusCode,
                etag: http.value(forHTTPHeaderField: "ETag"),
                rateLimitRemaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                data: data
            )
        } catch {
            return ReleaseLookupResult.classify(error: error)
        }
    }
}

// MARK: - Update checker

/// Owns the update state shown by the menu, the popover and the About card.
///
/// The API is contacted at most once per 24 hours for automatic checks, or when
/// the user asks. Failures are states, never alerts, and no retry loops run.
final class UpdateChecker {

    enum Keys {
        static let lastCheck = "tangent.updates.lastCheck"
        static let cachedRelease = "tangent.updates.release"
        static let etag = "tangent.updates.etag"
    }

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var installedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let versionText: String
    private let installed: ReleaseVersion
    private let architecture: MacArchitecture
    private let interval: TimeInterval
    private let now: () -> Date

    private(set) var state: UpdateState = .idle
    private(set) var lastChecked: Date?
    private(set) var isChecking = false

    /// Called on the main thread whenever `state` changes.
    var onChange: (() -> Void)?

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        version: String = UpdateChecker.installedVersion,
        architecture: MacArchitecture = .current,
        interval: TimeInterval = UpdateSchedule.interval,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.defaults = defaults
        self.versionText = version
        self.installed = ReleaseVersion(version) ?? ReleaseVersion(major: 0)
        self.architecture = architecture
        self.interval = interval
        self.now = now
        restoreCache()
    }

    // MARK: Checks

    /// Startup hook. Does nothing when the last successful check is recent or
    /// another check is already running.
    func checkIfNeeded() {
        guard !isChecking else { return }
        guard UpdateSchedule.isDue(last: lastChecked, now: now(), interval: interval) else {
            return
        }
        check(force: true)
    }

    /// `force` bypasses the interval, never an in-flight request.
    func check(force: Bool) {
        guard !isChecking else { return }
        if !force, !UpdateSchedule.isDue(last: lastChecked, now: now(), interval: interval) {
            return
        }

        isChecking = true
        state = .checking
        onChange?()

        let etag = defaults.string(forKey: Keys.etag)
        let lookup = ReleaseLookup(session: session, version: versionText)
        Task { @MainActor [weak self] in
            let result = await lookup.latest(etag: etag)
            guard let self else { return }
            self.finish(result)
        }
    }

    private func finish(_ result: ReleaseLookupResult) {
        isChecking = false

        switch result {
        case .release(let release, let etag):
            remember(release, etag: etag)
            state = UpdateDecision.evaluate(
                release: release,
                installed: installed,
                architecture: architecture
            )
        case .notModified:
            if let cached = cachedRelease() {
                lastChecked = now()
                defaults.set(lastChecked, forKey: Keys.lastCheck)
                state = UpdateDecision.evaluate(
                    release: cached,
                    installed: installed,
                    architecture: architecture
                )
            } else {
                state = .failed(message: "GitHub returned no release data.")
            }
        case .noRelease:
            state = .failed(message: "No published releases yet.")
        case .rateLimited:
            state = .rateLimited
        case .offline:
            state = .offline
        case .failed:
            state = .failed(message: "GitHub returned an unexpected response.")
        }

        onChange?()
    }

    // MARK: Cache

    private func remember(_ release: GitHubRelease, etag: String?) {
        if let data = try? JSONEncoder().encode(release) {
            defaults.set(data, forKey: Keys.cachedRelease)
        }
        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: Keys.etag)
        } else {
            defaults.removeObject(forKey: Keys.etag)
        }
        lastChecked = now()
        defaults.set(lastChecked, forKey: Keys.lastCheck)
    }

    private func cachedRelease() -> GitHubRelease? {
        guard let data = defaults.data(forKey: Keys.cachedRelease) else { return nil }
        return try? JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// Makes a cached answer visible immediately at launch, before any network
    /// request. The next check updates it in place.
    private func restoreCache() {
        lastChecked = defaults.object(forKey: Keys.lastCheck) as? Date
        guard let cached = cachedRelease() else { return }
        state = UpdateDecision.evaluate(
            release: cached,
            installed: installed,
            architecture: architecture
        )
    }
}
