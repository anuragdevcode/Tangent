import AppKit
import Carbon.HIToolbox

/// Global shortcuts for the menu-bar app.
///
/// The app is an `LSUIElement` accessory, so it has no Dock icon and its menu
/// is only reachable through the status item. Carbon hot keys are used instead
/// of `NSEvent` monitors because they work while another app is frontmost and
/// do not need Accessibility or Input Monitoring permission.
///
/// Each action has a default Control-Option combination and can be rebound.
/// Bindings persist in `UserDefaults`. Registration failures are recorded
/// rather than thrown, so one shortcut already taken by another app does not
/// disable the rest.
final class HotkeyManager {

    enum Action: String, CaseIterable {
        case togglePause
        case nextWallpaper
        case openLibrary
        case stopWallpaper

        var title: String {
            switch self {
            case .togglePause: return "Pause / Resume"
            case .nextWallpaper: return "Next Wallpaper"
            case .openLibrary: return "Open Library"
            case .stopWallpaper: return "Stop Wallpaper"
            }
        }

        var keyCode: UInt32 {
            switch self {
            case .togglePause: return UInt32(kVK_Space)
            case .nextWallpaper: return UInt32(kVK_RightArrow)
            case .openLibrary: return UInt32(kVK_ANSI_L)
            case .stopWallpaper: return UInt32(kVK_ANSI_Period)
            }
        }

        /// Control-Option is used by very few apps, unlike Command-based
        /// combinations which would collide with normal menu shortcuts.
        var modifiers: UInt32 { UInt32(controlKey | optionKey) }

        var keyLabel: String {
            switch self {
            case .togglePause: return "Space"
            case .nextWallpaper: return "→"
            case .openLibrary: return "L"
            case .stopWallpaper: return "."
            }
        }

        /// The factory binding. `display` is kept for the defaults and tests;
        /// the manager's current binding should be used in the UI.
        var display: String { "⌃⌥" + keyLabel }

        var defaultBinding: KeyBinding {
            KeyBinding(keyCode: keyCode, modifiers: modifiers)
        }

        /// Carbon hot-key identifiers are numeric, so actions get a stable ID.
        var identifier: UInt32 {
            UInt32((Self.allCases.firstIndex(of: self) ?? 0) + 1)
        }

        static func action(for identifier: UInt32) -> Action? {
            allCases.first { $0.identifier == identifier }
        }
    }

    /// A key code plus Carbon modifier flags. Stored as-is so registration and
    /// the recorder use the same representation.
    struct KeyBinding: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// Converts an AppKit key event. Returns nil when no modifier is held;
        /// validation explains why the binding cannot be used.
        init?(event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            guard modifiers != 0 else { return nil }

            self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        }

        /// Modifier keys alone are not valid hot keys.
        var isModifierOnly: Bool {
            Self.modifierKeyCodes.contains(keyCode)
        }

        /// Control or Option is required. This keeps global shortcuts from
        /// shadowing ordinary Command menu shortcuts in every app.
        var hasRequiredModifier: Bool {
            (modifiers & UInt32(controlKey | optionKey)) != 0
        }

        var modifierDisplay: String {
            var text = ""
            if (modifiers & UInt32(controlKey)) != 0 { text += "⌃" }
            if (modifiers & UInt32(optionKey)) != 0 { text += "⌥" }
            if (modifiers & UInt32(shiftKey)) != 0 { text += "⇧" }
            if (modifiers & UInt32(cmdKey)) != 0 { text += "⌘" }
            return text
        }

        var display: String { modifierDisplay + Self.label(for: keyCode) }

        private static let modifierKeyCodes: Set<UInt32> = [
            UInt32(kVK_Command), UInt32(kVK_RightCommand),
            UInt32(kVK_Shift), UInt32(kVK_RightShift),
            UInt32(kVK_Option), UInt32(kVK_RightOption),
            UInt32(kVK_Control), UInt32(kVK_RightControl),
            UInt32(kVK_CapsLock), UInt32(kVK_Function),
        ]

        /// Physical key labels. Shifted characters are intentionally not
        /// translated: `⇧1` stays a physical-key description, which is what the
        /// recorder captured and what Carbon registers.
        private static let keyLabels: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_S: "S", kVK_ANSI_D: "D", kVK_ANSI_F: "F",
            kVK_ANSI_H: "H", kVK_ANSI_G: "G", kVK_ANSI_Z: "Z", kVK_ANSI_X: "X",
            kVK_ANSI_C: "C", kVK_ANSI_V: "V", kVK_ANSI_B: "B", kVK_ANSI_Q: "Q",
            kVK_ANSI_W: "W", kVK_ANSI_E: "E", kVK_ANSI_R: "R", kVK_ANSI_Y: "Y",
            kVK_ANSI_T: "T", kVK_ANSI_O: "O", kVK_ANSI_U: "U", kVK_ANSI_I: "I",
            kVK_ANSI_P: "P", kVK_ANSI_L: "L", kVK_ANSI_J: "J", kVK_ANSI_K: "K",
            kVK_ANSI_N: "N", kVK_ANSI_M: "M",

            kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
            kVK_ANSI_9: "9", kVK_ANSI_0: "0",

            kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_Quote: "'", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
            kVK_ANSI_Slash: "/", kVK_ANSI_Period: ".",
            kVK_ANSI_Grave: "`",
            kVK_ISO_Section: "§",

            kVK_Return: "Return", kVK_Tab: "Tab", kVK_Space: "Space",
            kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete",
            kVK_Escape: "Escape", kVK_Help: "Help",
            kVK_Home: "Home", kVK_End: "End",
            kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_DownArrow: "↓", kVK_UpArrow: "↑",

            kVK_ANSI_Keypad0: "Keypad 0", kVK_ANSI_Keypad1: "Keypad 1",
            kVK_ANSI_Keypad2: "Keypad 2", kVK_ANSI_Keypad3: "Keypad 3",
            kVK_ANSI_Keypad4: "Keypad 4", kVK_ANSI_Keypad5: "Keypad 5",
            kVK_ANSI_Keypad6: "Keypad 6", kVK_ANSI_Keypad7: "Keypad 7",
            kVK_ANSI_Keypad8: "Keypad 8", kVK_ANSI_Keypad9: "Keypad 9",
            kVK_ANSI_KeypadDecimal: "Keypad .", kVK_ANSI_KeypadMultiply: "Keypad *",
            kVK_ANSI_KeypadPlus: "Keypad +", kVK_ANSI_KeypadClear: "Keypad Clear",
            kVK_ANSI_KeypadDivide: "Keypad /", kVK_ANSI_KeypadEnter: "Keypad Enter",
            kVK_ANSI_KeypadMinus: "Keypad -", kVK_ANSI_KeypadEquals: "Keypad =",

            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",

            kVK_VolumeUp: "Volume Up", kVK_VolumeDown: "Volume Down",
            kVK_Mute: "Mute",
        ]

        static func label(for keyCode: UInt32) -> String {
            keyLabels[Int(keyCode)] ?? "Key \(keyCode)"
        }
    }

    enum BindingError: Error, Equatable {
        case missingModifier
        case modifierOnly
        case reservedKey(String)
        case duplicate(Action)

        var message: String {
            switch self {
            case .missingModifier:
                return "Use Control or Option, plus another key."
            case .modifierOnly:
                return "That is only a modifier key. Add a letter, number or function key."
            case .reservedKey(let name):
                return "\(name) is reserved for cancelling the shortcut recorder."
            case .duplicate(let action):
                return "Already used by \(action.title)."
            }
        }
    }

    static let enabledKey = "tangent.hotkeys.enabled"
    static let bindingsKey = "tangent.hotkeys.bindings"

    private let defaults: UserDefaults
    private let signature: OSType = 0x54414E54 // 'TANT'

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var registered: Set<Action> = []
    private(set) var failures: [Action: OSStatus] = [:]
    private(set) var handlerStatus: OSStatus = noErr

    /// Only custom bindings are stored; missing entries fall back to defaults.
    private(set) var bindings: [Action: KeyBinding] = [:]

    var onAction: ((Action) -> Void)?

    /// Persisted. Changing it re-registers immediately.
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            refresh()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)

        let loaded = Self.loadBindings(from: defaults)
        let sanitized = Self.sanitize(loaded)
        self.bindings = sanitized
        if sanitized != loaded {
            saveBindings()
        }
    }

    deinit { stop() }

    // MARK: - Lifecycle

    /// Registers the shortcuts when the user has enabled them.
    func start() { refresh() }

    func refresh() {
        stop()
        guard isEnabled else { return }
        registerAll()
    }

    /// Used by `--hotkey-status`: proves the Carbon path works without
    /// changing the user's saved preference.
    func registerForDiagnostics() {
        stop()
        registerAll()
    }

    func stop() {
        for reference in hotKeyRefs {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
        registered.removeAll()
        failures.removeAll()
        handlerStatus = noErr

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    var registeredActions: [Action] {
        Action.allCases.filter { registered.contains($0) }
    }

    var isActive: Bool { !registered.isEmpty }

    // MARK: - Bindings

    func binding(for action: Action) -> KeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    func isCustomized(_ action: Action) -> Bool {
        guard let binding = bindings[action] else { return false }
        return binding != action.defaultBinding
    }

    func display(for action: Action) -> String {
        binding(for: action).display
    }

    /// Validates, persists and immediately re-registers. The recorder keeps
    /// listening when this throws, so a conflict can be corrected in place.
    func setBinding(_ binding: KeyBinding, for action: Action) throws {
        if binding.isModifierOnly { throw BindingError.modifierOnly }
        guard binding.hasRequiredModifier else { throw BindingError.missingModifier }
        if binding.keyCode == UInt32(kVK_Escape) {
            throw BindingError.reservedKey("Escape")
        }

        for other in Action.allCases where other != action {
            if self.binding(for: other) == binding || other.defaultBinding == binding {
                throw BindingError.duplicate(other)
            }
        }

        if binding == action.defaultBinding {
            bindings.removeValue(forKey: action)
        } else {
            bindings[action] = binding
        }
        saveBindings()
        refresh()
    }

    func resetBinding(for action: Action) {
        bindings.removeValue(forKey: action)
        saveBindings()
        refresh()
    }

    func resetAllBindings() {
        bindings.removeAll()
        defaults.removeObject(forKey: Self.bindingsKey)
        refresh()
    }

    private func saveBindings() {
        guard !bindings.isEmpty else {
            defaults.removeObject(forKey: Self.bindingsKey)
            return
        }
        let encoded = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) }
        )
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Self.bindingsKey)
        }
    }

    private static func loadBindings(from defaults: UserDefaults) -> [Action: KeyBinding] {
        guard let data = defaults.data(forKey: bindingsKey),
              let decoded = try? JSONDecoder().decode([String: KeyBinding].self, from: data)
        else { return [:] }

        var result: [Action: KeyBinding] = [:]
        for (rawAction, binding) in decoded {
            guard let action = Action(rawValue: rawAction) else { continue }
            result[action] = binding
        }
        return result
    }

    /// Drops corrupt, redundant or conflicting entries from older builds or
    /// hand-edited defaults. Later actions lose a conflict, deterministically.
    private static func sanitize(_ raw: [Action: KeyBinding]) -> [Action: KeyBinding] {
        var result: [Action: KeyBinding] = [:]
        for action in Action.allCases {
            guard let binding = raw[action] else { continue }
            guard !binding.isModifierOnly,
                  binding.hasRequiredModifier,
                  binding.keyCode != UInt32(kVK_Escape),
                  binding != action.defaultBinding
            else { continue }

            let conflicts = Action.allCases.contains { other in
                guard other != action else { return false }
                let effective = result[other] ?? other.defaultBinding
                return other.defaultBinding == binding || effective == binding
            }
            guard !conflicts else { continue }
            result[action] = binding
        }
        return result
    }

    // MARK: - Registration

    private func registerAll() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else { return }

        for action in Action.allCases {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: signature, id: action.identifier)
            let binding = binding(for: action)
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                hotKeyRefs.append(reference)
                registered.insert(action)
            } else {
                failures[action] = status
            }
        }
    }

    /// Carbon event IDs are numeric; this maps them back to actions. Internal
    /// so the self-tests can exercise dispatch without posting real key events.
    func dispatch(identifier: UInt32) {
        guard let action = Action.action(for: identifier) else { return }
        onAction?(action)
    }

    /// Human-readable status for Settings and `--hotkey-status`.
    var statusDescription: String {
        if !isEnabled { return "Global shortcuts are off." }
        if handlerStatus != noErr {
            return "Could not install the shortcut handler (error \(handlerStatus))."
        }
        if failures.isEmpty {
            return "All \(Action.allCases.count) shortcuts are registered."
        }
        let names = failures.keys.map(\.title).sorted().joined(separator: ", ")
        return "Unavailable (already used by another app): \(names)."
    }
}

/// Carbon event handler. The manager is passed as `userData`, so this stays a
/// plain C function with no captured state.
private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.dispatch(identifier: identifier.id)
    return noErr
}
