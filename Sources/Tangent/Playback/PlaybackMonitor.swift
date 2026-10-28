import AppKit
import IOKit.ps

/// Reasons playback can be suspended. Wallpapers resume only when every
/// active reason has cleared, so a user pause is not undone by a fullscreen
/// app closing.
enum PauseReason: Hashable {
    case user
    case fullscreen
    case battery
    case lock
}

/// Playback rules: pause on a fullscreen app, on battery power, or on lock.
final class PlaybackMonitor {

    struct Policy: Codable, Equatable {
        var pauseOnFullscreen: Bool = true
        var pauseOnBattery: Bool = true
        var pauseOnLock: Bool = true
    }

    private let key = "tangent.playbackPolicy"
    private let defaults: UserDefaults
    private(set) var policy: Policy

    var onPause: ((PauseReason) -> Void)?
    var onResume: ((PauseReason) -> Void)?

    private var timer: Timer?
    private var isFullscreenAppActive = false
    private var isOnBattery = false
    private var isLocked = false
    private var lastEmitted: [PauseReason: Bool] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Policy.self, from: data) {
            self.policy = decoded
        } else {
            self.policy = Policy()
        }
    }

    func start() {
        stop()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func setPolicy(_ policy: Policy) {
        self.policy = policy
        if let data = try? JSONEncoder().encode(policy) {
            defaults.set(data, forKey: key)
        }
        evaluate()
    }

    // MARK: - Evaluation

    private func evaluate() {
        isFullscreenAppActive = Self.fullscreenAppIsActive()
        isOnBattery = Self.isOnBatteryPower()
        publish(.fullscreen, active: isFullscreenAppActive && policy.pauseOnFullscreen)
        publish(.battery, active: isOnBattery && policy.pauseOnBattery)
        publish(.lock, active: isLocked && policy.pauseOnLock)
    }

    private func publish(_ reason: PauseReason, active: Bool) {
        let previous = lastEmitted[reason] ?? false
        guard previous != active else { return }
        lastEmitted[reason] = active
        if active {
            onPause?(reason)
        } else {
            onResume?(reason)
        }
    }

    @objc private func screensDidSleep() {
        isLocked = true
        publish(.lock, active: policy.pauseOnLock)
    }

    @objc private func screensDidWake() {
        isLocked = false
        publish(.lock, active: false)
    }

    @objc private func screenLocked() {
        isLocked = true
        publish(.lock, active: policy.pauseOnLock)
    }

    @objc private func screenUnlocked() {
        isLocked = false
        publish(.lock, active: false)
    }

    // MARK: - System queries

    /// True when the frontmost app owns an opaque, normal-level window that
    /// covers (almost) the whole main display — i.e. a fullscreen app, game,
    /// or video. Backs the pause-on-fullscreen rule.
    static func fullscreenAppIsActive() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier { return false }

        guard let screen = NSScreen.main else { return false }
        let screenFrame = screen.frame
        let requiredArea = screenFrame.width * screenFrame.height * 0.92

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontmost.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            if bounds.width * bounds.height >= requiredArea {
                return true
            }
        }
        return false
    }

    static func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (source as String) == "Battery Power"
    }
}
