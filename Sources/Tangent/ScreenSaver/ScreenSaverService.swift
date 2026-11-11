import AppKit
import Foundation

/// Installs, updates and removes the user's copy of `Tangent.saver`.
///
/// The screen saver itself is a separate bundle built from the same players.
/// This service keeps its configuration in step with the live layout and owns
/// the one persisted on/off switch, so the app never has to guess whether the
/// bundle is present.
final class ScreenSaverService {
    static let enabledKey = "tangent.screenSaver.enabled"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let storage: ScreenSaverStorage
    private let stager: ScreenSaverStager
    private let bundledSaverURL: URL?

    /// Called after the switch or the installation changes, on the main queue.
    var onChange: (() -> Void)?

    private(set) var isBusy = false
    private(set) var lastError: String?

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledSaverURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        let storage = ScreenSaverStorage(homeDirectory: homeDirectory)
        self.storage = storage
        self.stager = ScreenSaverStager(storage: storage, fileManager: fileManager)
        self.bundledSaverURL = bundledSaverURL
            ?? Bundle.main.resourceURL?.appendingPathComponent(
                ScreenSaverStorage.bundleName,
                isDirectory: true
            )
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: storage.installedBundleURL.path)
    }

    var installedURL: URL { storage.installedBundleURL }

    var configurationURL: URL { storage.configurationURL }

    /// A short, user-facing state for the Settings and Automation rows.
    var statusDescription: String {
        if isBusy {
            return "Installing the screen saver…"
        }
        if let lastError {
            return "Couldn’t update the screen saver. \(lastError)"
        }
        if isEnabled, isInstalled {
            return "Installed. Choose Tangent in System Settings ▸ Screen Saver."
        }
        if isEnabled {
            return "Enabled, but Tangent.saver is missing. Turn this off and on to reinstall."
        }
        return "Show the active wallpaper when your Mac is idle. Choose Tangent afterwards in System Settings."
    }

    /// The switch in Settings, Automation or the menu bar.
    @discardableResult
    func setEnabled(_ enabled: Bool, configuration: ScreenSaverConfiguration) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer {
            isBusy = false
            onChange?()
        }

        do {
            if enabled {
                try install(prepared(configuration))
                defaults.set(true, forKey: Self.enabledKey)
            } else {
                try storage.removeInstalledBundle()
                defaults.set(false, forKey: Self.enabledKey)
            }
            lastError = nil
            return true
        } catch {
            // A failed enablement must not leave the switch looking successful.
            if enabled {
                try? storage.removeInstalledBundle()
                defaults.set(false, forKey: Self.enabledKey)
            }
            lastError = error.localizedDescription
            return false
        }
    }

    /// Called on launch and after every layout change. When the user opted in,
    /// this repairs a missing bundle and always refreshes the config.
    func synchronize(_ configuration: ScreenSaverConfiguration) {
        guard isEnabled else { return }
        let configuration = prepared(configuration)
        do {
            if !isInstalled {
                try install(configuration)
            } else if let bundledSaverURL,
                      fileManager.fileExists(atPath: bundledSaverURL.path),
                      !storage.installedBundleMatches(bundledSaverURL, fileManager: fileManager) {
                try install(configuration)
            } else {
                try storage.save(configuration)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func install(_ configuration: ScreenSaverConfiguration) throws {
        guard let bundledSaverURL,
              fileManager.fileExists(atPath: bundledSaverURL.path)
        else {
            throw ScreenSaverError.bundleMissing
        }
        try storage.install(from: bundledSaverURL, configuration: configuration)
    }

    /// Stage user-selected media where the saver can read it, and never throw
    /// away a working snapshot just because a launch had no layout yet.
    private func prepared(_ configuration: ScreenSaverConfiguration) -> ScreenSaverConfiguration {
        let staged = stager.prepare(configuration)
        if staged.layout.hasPlayableConfig { return staged }
        if let existing = storage.load(), existing.layout.hasPlayableConfig {
            return existing
        }
        return staged
    }
}

enum ScreenSaverError: LocalizedError {
    case bundleMissing

    var errorDescription: String? {
        switch self {
        case .bundleMissing:
            return "This build does not contain Tangent.saver."
        }
    }
}
