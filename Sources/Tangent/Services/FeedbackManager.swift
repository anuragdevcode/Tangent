import AppKit

// MARK: - System information

/// Thin, crash-free wrappers over the few `sysctl` values Tangent reports.
/// Every lookup can fail; callers treat a missing value as "unknown".
enum SystemInfo {

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static var compiledArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - Diagnostics

/// The complete set of machine facts Tangent is willing to report. No serial
/// number, Apple ID, username, home path, installed apps or IP address.
struct Diagnostics: Equatable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let shortMacOSVersion: String
    let hardwareModel: String?
    let chip: String?
    let isAppleSilicon: Bool?
    let architecture: String
    let isTranslated: Bool?

    var hardwareDescription: String {
        var parts: [String] = []
        if let hardwareModel, !hardwareModel.isEmpty { parts.append(hardwareModel) }
        if let chip, !chip.isEmpty { parts.append(chip) }
        return parts.isEmpty ? "Unavailable" : parts.joined(separator: " · ")
    }

    var architectureDescription: String {
        if isTranslated == true {
            return "\(architecture) (Rosetta)"
        }
        if let isAppleSilicon {
            return isAppleSilicon ? "Apple Silicon · \(architecture)" : "Intel · \(architecture)"
        }
        return architecture
    }
}

/// Collects diagnostics with injectable inputs, so formatting can be tested
/// without depending on the machine running the test.
struct DiagnosticsCollector {

    var info: [String: Any]
    var operatingSystemVersion: () -> String
    var shortOperatingSystemVersion: () -> String
    var sysctlString: (String) -> String?
    var sysctlInt: (String) -> Int?
    var architecture: String

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        operatingSystemVersion: @escaping () -> String = {
            ProcessInfo.processInfo.operatingSystemVersionString
        },
        shortOperatingSystemVersion: @escaping () -> String = {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        },
        sysctlString: @escaping (String) -> String? = SystemInfo.sysctlString,
        sysctlInt: @escaping (String) -> Int? = SystemInfo.sysctlInt,
        architecture: String = SystemInfo.compiledArchitecture
    ) {
        self.info = info
        self.operatingSystemVersion = operatingSystemVersion
        self.shortOperatingSystemVersion = shortOperatingSystemVersion
        self.sysctlString = sysctlString
        self.sysctlInt = sysctlInt
        self.architecture = architecture
    }

    func collect() -> Diagnostics {
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String ?? "Unknown"

        let arm64 = sysctlInt("hw.optional.arm64").map { $0 != 0 }
        let translated = sysctlInt("sysctl.proc_translated").map { $0 != 0 }

        let appleSilicon: Bool?
        if let arm64 {
            appleSilicon = arm64
        } else if architecture == "arm64" {
            appleSilicon = true
        } else if architecture == "x86_64" {
            appleSilicon = false
        } else {
            appleSilicon = nil
        }

        return Diagnostics(
            appVersion: version,
            buildNumber: build,
            macOSVersion: operatingSystemVersion(),
            shortMacOSVersion: shortOperatingSystemVersion(),
            hardwareModel: sysctlString("hw.model"),
            chip: sysctlString("machdep.cpu.brand_string"),
            isAppleSilicon: appleSilicon,
            architecture: architecture,
            isTranslated: translated
        )
    }
}

// MARK: - Feedback

/// Bug-report URL construction and the small, opt-in diagnostic block.
///
/// `GitHubRepo.bugReportTemplate` is a YAML issue form. GitHub does not accept
/// a prefilled `body` for issue forms, so the diagnostics are offered as a
/// clipboard block and the link carries only the template and title. Nothing is
/// transmitted anywhere until the user submits the issue.
final class FeedbackManager {

    static let privacyNote = """
    This summary contains the Tangent version, macOS version, hardware model and \
    architecture. It does not include your name, home folder, serial number, IP \
    address or any files. Nothing is sent until you submit the issue on GitHub.
    """

    private let collector: DiagnosticsCollector

    init(collector: DiagnosticsCollector = DiagnosticsCollector()) {
        self.collector = collector
    }

    func collectDiagnostics() -> Diagnostics {
        collector.collect()
    }

    /// Markdown that can be pasted into the issue form's Diagnostics field.
    func diagnosticText(_ diagnostics: Diagnostics) -> String {
        [
            "### Environment",
            "- Tangent: \(diagnostics.appVersion) (\(diagnostics.buildNumber))",
            "- macOS: \(diagnostics.macOSVersion)",
            "- Hardware: \(diagnostics.hardwareDescription)",
            "- Architecture: \(diagnostics.architectureDescription)",
        ].joined(separator: "\n")
    }

    func issueTitle(_ diagnostics: Diagnostics) -> String {
        let title = "Bug report — Tangent \(diagnostics.appVersion) "
            + "(\(diagnostics.buildNumber)), macOS \(diagnostics.shortMacOSVersion)"
        return String(title.prefix(120))
    }

    /// Template and title only. `body` is intentionally absent: GitHub issue
    /// forms ignore it, and the UI never claims otherwise.
    func bugReportURL(title: String) -> URL {
        var components = URLComponents(
            url: GitHubRepo.bugReportForm,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "template", value: GitHubRepo.bugReportTemplate),
            URLQueryItem(name: "title", value: title),
        ]
        return components?.url ?? GitHubRepo.bugReportForm
    }

    func currentBugReportURL() -> URL {
        bugReportURL(title: issueTitle(collectDiagnostics()))
    }

    @discardableResult
    func copyDiagnostics(_ diagnostics: Diagnostics) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(diagnosticText(diagnostics), forType: .string)
    }

    func openBugReport() {
        ExternalLink.open(currentBugReportURL())
    }

    func openDiscussions() {
        ExternalLink.open(GitHubRepo.discussions)
    }

    func openRepository() {
        ExternalLink.open(GitHubRepo.repository)
    }

    func openReleases() {
        ExternalLink.open(GitHubRepo.releases)
    }
}
