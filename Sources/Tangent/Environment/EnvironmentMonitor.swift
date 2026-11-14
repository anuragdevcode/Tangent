import AppKit
import CoreAudio
import Foundation

/// Ambient state a wallpaper can react to.
///
/// Everything here is derived locally and without a permission prompt: the
/// pointer comes from `NSEvent.mouseLocation`, audio presence comes from the
/// default output device's `DeviceIsRunningSomewhere` property, and the rest is
/// clock, appearance and power state. No capture, no location, no network.
struct EnvironmentSnapshot {
    /// Pointer in screen coordinates (origin bottom-left, like AppKit).
    var pointerScreen: CGPoint
    /// True while any process is using the default output device. A short hold
    /// keeps track changes from flickering, but this is presence, not a
    /// waveform: it cannot be beat-synced.
    var isAudioPlaying: Bool
    /// Fraction of the local day, 0 at midnight and 0.5 at noon.
    var dayPhase: Double
    var isDark: Bool
    var reduceMotion: Bool
    var lowPowerMode: Bool
    var timestamp: TimeInterval
}

/// Clock helpers shared by the app and the screen saver.
enum DayPhase {
    static func value(hour: Int, minute: Int = 0, second: Int = 0) -> Double {
        let seconds = max(0, min(23, hour)) * 3600
            + max(0, min(59, minute)) * 60
            + max(0, min(59, second))
        return Double(seconds) / 86_400.0
    }

    static func value(for date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return value(
            hour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0
        )
    }
}

/// Converts an AppKit screen point into normalized top-left coordinates.
///
/// Used by tests and by the engine when a display's frame is known. The
/// WebWallpaper path uses the view's own coordinate conversion instead, so a
/// preview inside a window gets the same treatment as a full-screen window.
enum PointerGeometry {
    static func normalized(
        point: CGPoint,
        in frame: CGRect
    ) -> (point: CGPoint, inside: Bool) {
        guard frame.width > 0, frame.height > 0 else {
            return (CGPoint(x: 0.5, y: 0.5), false)
        }
        let x = (point.x - frame.minX) / frame.width
        let y = 1 - (point.y - frame.minY) / frame.height
        let inside = (0...1).contains(x) && (0...1).contains(y)
        return (
            CGPoint(
                x: min(max(x, 0), 1),
                y: min(max(y, 0), 1)
            ),
            inside
        )
    }
}

/// Permission-free "is the Mac making sound?" probe.
///
/// It inspects the default output device rather than capturing audio, so it
/// works in the sandboxed screen-saver host and never triggers a privacy
/// prompt. Callers may inject a provider for tests.
final class AudioActivityMonitor {
    typealias RunningProvider = () -> Bool

    private let provider: RunningProvider
    private let hold: TimeInterval
    private var timer: Timer?
    private var lastRunning = Date.distantPast
    private(set) var isPlaying = false

    init(
        provider: @escaping RunningProvider = AudioActivityMonitor.outputIsRunning,
        hold: TimeInterval = 1.5
    ) {
        self.provider = provider
        self.hold = hold
    }

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        lastRunning = Date.distantPast
    }

    /// Exposed so tests can advance the hold window deterministically.
    func poll(now: Date = Date()) {
        if provider() {
            lastRunning = now
            isPlaying = true
        } else if isPlaying, now.timeIntervalSince(lastRunning) >= hold {
            isPlaying = false
        }
    }

    /// True when the default output device reports that some process is
    /// producing audio. Muted media and paused players report false.
    static func outputIsRunning() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &size,
            &device
        ) == noErr else { return false }

        var running = UInt32(0)
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            device,
            &runningAddress,
            0,
            nil,
            &runningSize,
            &running
        ) == noErr else { return false }
        return running != 0
    }
}

/// One 30 Hz timer and one 2-second audio poll shared by every wallpaper that
/// asked for ambient state. It starts on the first observer and stops on the
/// last, so a static web pack pays nothing.
final class EnvironmentMonitor {
    static let shared = EnvironmentMonitor()

    private let audio = AudioActivityMonitor()
    private var observers: [UUID: (EnvironmentSnapshot) -> Void] = [:]
    private var timer: Timer?

    var observerCount: Int { observers.count }

    func addObserver(_ body: @escaping (EnvironmentSnapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = body
        if timer == nil { start() }
        if let snapshot = currentSnapshot() {
            body(snapshot)
        }
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
        guard observers.isEmpty else { return }
        stop()
    }

    private func start() {
        audio.start()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        audio.stop()
    }

    private func tick() {
        guard let snapshot = currentSnapshot(), !observers.isEmpty else { return }
        for body in observers.values {
            body(snapshot)
        }
    }

    private func currentSnapshot() -> EnvironmentSnapshot? {
        let now = Date()
        let appearance = NSApplication.shared.effectiveAppearance
        return EnvironmentSnapshot(
            pointerScreen: NSEvent.mouseLocation,
            isAudioPlaying: audio.isPlaying,
            dayPhase: DayPhase.value(for: now),
            isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            timestamp: now.timeIntervalSince1970
        )
    }
}
