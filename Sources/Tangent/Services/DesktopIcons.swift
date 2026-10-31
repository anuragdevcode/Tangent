import Foundation

/// Hides or shows the items Finder draws on the desktop.
///
/// macOS has no public API for this, so the service changes Finder's own
/// `CreateDesktop` preference and asks Finder to relaunch. That is the same
/// setting behind Finder > Settings > General > "Show items on Desktop".
final class DesktopIcons {

    enum State: Equatable {
        case visible
        case hidden
        case failed(String)

        var isHidden: Bool { self == .hidden }

        var failure: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    /// The two commands and the preference read, injectable so the tests never
    /// touch the real Finder setting.
    struct Store {
        var isHidden: () throws -> Bool
        var setHidden: (Bool) throws -> Void
        var restartFinder: () throws -> Void
    }

    private let store: Store
    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue

    private(set) var state = State.visible
    private(set) var isBusy = false

    /// Called on the callback queue whenever the state or busy flag changes.
    var onChange: (() -> Void)?

    init(
        store: Store = .system,
        queue: DispatchQueue = DispatchQueue(
            label: "app.tangent.desktop-icons",
            qos: .userInitiated
        ),
        callbackQueue: DispatchQueue = .main
    ) {
        self.store = store
        self.queue = queue
        self.callbackQueue = callbackQueue
        refresh()
    }

    var isHidden: Bool { state.isHidden }

    /// Re-reads the setting Finder actually uses. A missing key is normal:
    /// macOS treats it as "show desktop icons", which is also Finder's default.
    func refresh() {
        do {
            state = try store.isHidden() ? .hidden : .visible
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Applies the setting off the main thread, because restarting Finder can
    /// take a moment, then reports the state Finder ended up with.
    func setHidden(_ hidden: Bool, completion: (() -> Void)? = nil) {
        guard !isBusy else { return }

        isBusy = true
        notifyChange()

        let store = self.store
        queue.async { [weak self] in
            let result: Result<Void, Error>
            do {
                try store.setHidden(hidden)
                try store.restartFinder()
                result = .success(())
            } catch {
                result = .failure(error)
            }

            self?.callbackQueue.async {
                guard let self else { return }
                self.isBusy = false
                switch result {
                case .success:
                    self.refresh()
                case .failure(let error):
                    self.state = .failed(Self.message(for: error))
                }
                self.notifyChange()
                completion?()
            }
        }
    }

    private func notifyChange() {
        let onChange = self.onChange
        callbackQueue.async {
            onChange?()
        }
    }

    private static func message(for error: Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "The desktop icon setting could not be changed." : text
    }
}

// MARK: - System store

extension DesktopIcons.Store {

    static var system: DesktopIcons.Store {
        DesktopIcons.Store(
            isHidden: {
                let result = try DesktopIcons.Store.run(
                    "/usr/bin/defaults",
                    ["read", "com.apple.finder", "CreateDesktop"]
                )
                // Exit 1 means Finder has never written the key, so its icons
                // are visible. Any other failure is a real failure.
                if result.status == 1 { return false }
                guard result.status == 0 else {
                    throw DesktopIcons.CommandError(
                        "Finder’s desktop icon setting could not be read."
                    )
                }
                switch result.output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() {
                case "0", "false", "no":
                    return true
                case "1", "true", "yes":
                    return false
                default:
                    throw DesktopIcons.CommandError(
                        "Finder returned an unexpected desktop icon setting."
                    )
                }
            },
            setHidden: { hidden in
                let result = try DesktopIcons.Store.run(
                    "/usr/bin/defaults",
                    [
                        "write", "com.apple.finder", "CreateDesktop", "-bool",
                        hidden ? "false" : "true",
                    ]
                )
                guard result.status == 0 else {
                    throw DesktopIcons.CommandError(
                        "Finder’s desktop icon setting could not be saved."
                    )
                }
            },
            restartFinder: {
                let result = try DesktopIcons.Store.run("/usr/bin/killall", ["Finder"])
                // killall exits 1 when Finder is already gone; the preference
                // still applies the next time Finder starts, so that is fine.
                guard result.status == 0 || result.status == 1 else {
                    throw DesktopIcons.CommandError(
                        "Finder could not be restarted. The setting will apply when it reopens."
                    )
                }
            }
        )
    }

    fileprivate struct CommandResult {
        let status: Int32
        let output: String
    }

    fileprivate static func run(_ tool: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw DesktopIcons.CommandError(
                "The system tool \(URL(fileURLWithPath: tool).lastPathComponent) could not run."
            )
        }
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

extension DesktopIcons {
    fileprivate struct CommandError: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }
}
