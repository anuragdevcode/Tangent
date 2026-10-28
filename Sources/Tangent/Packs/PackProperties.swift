import Foundation

/// One entry in a pack's control file.
///
/// The control set and required fields follow the pack format's property
/// schema — all eight types are covered.
enum ControlSpec: Equatable {
    case slider(text: String, min: Double, max: Double, step: Double, value: Double)
    case textbox(text: String, value: String)
    case dropdown(text: String, items: [String], value: Int)
    case folderDropdown(text: String, filter: String, folder: String, value: String)
    case button(text: String, value: String)
    case label(text: String)
    case color(text: String, value: String)
    case checkbox(text: String, value: Bool)

    var kindName: String {
        switch self {
        case .slider: return "slider"
        case .textbox: return "textbox"
        case .dropdown: return "dropdown"
        case .folderDropdown: return "folderDropdown"
        case .button: return "button"
        case .label: return "label"
        case .color: return "color"
        case .checkbox: return "checkbox"
        }
    }

    var title: String {
        switch self {
        case .slider(let text, _, _, _, _): return text
        case .textbox(let text, _): return text
        case .dropdown(let text, _, _): return text
        case .folderDropdown(let text, _, _, _): return text
        case .button(let text, _): return text
        case .label(let text): return text
        case .color(let text, _): return text
        case .checkbox(let text, _): return text
        }
    }

    /// Buttons and labels are user-interaction only; their values are never
    /// pushed to the wallpaper on load.
    var isUserInteractionOnly: Bool {
        switch self {
        case .button, .label: return true
        default: return false
        }
    }

    /// What a user interaction with this control sends over the bridge.
    ///
    /// A button sends `true` (not its `value`) and a `folderDropdown` sends the
    /// file name only when it exists, otherwise `null`. A label sends nothing.
    func interactionValue(root: URL?) -> JSONValue? {
        switch self {
        case .slider(_, _, _, _, let value):
            return .number(value)
        case .textbox(_, let value):
            return .string(value)
        case .dropdown(_, _, let value):
            return .number(Double(value))
        case .checkbox(_, let value):
            return .bool(value)
        case .color(_, let value):
            return .string(value)
        case .button:
            return .bool(true)
        case .label:
            return nil
        case .folderDropdown(_, _, let folder, let value):
            guard let root, !value.isEmpty else { return .null }
            let candidate = root
                .appendingPathComponent(folder)
                .appendingPathComponent(value)
            return FileManager.default.fileExists(atPath: candidate.path)
                ? .string(value)
                : .null
        }
    }
}

struct PropertyControl: Equatable {
    let name: String
    let spec: ControlSpec
    /// Optional `help` text from the properties file (shown as a hint).
    let help: String?

    init(name: String, spec: ControlSpec, help: String? = nil) {
        self.name = name
        self.spec = spec
        self.help = help
    }

    /// Value pushed when the user interacts with this control.
    func interactionValue(root: URL?) -> JSONValue? {
        spec.interactionValue(root: root)
    }
}

enum PackProperties {

    /// Parses a pack's control file.
    ///
    /// Ordering: the file is a JSON object, so key order is not preserved by
    /// any standard parser. Controls are returned sorted by key for a stable UI.
    static func parse(_ json: JSONValue) -> [PropertyControl] {
        guard let object = json.objectValue else { return [] }
        var controls: [PropertyControl] = []
        for name in object.keys.sorted() {
            guard let body = object[name]?.objectValue,
                  let type = body["type"]?.stringValue,
                  let spec = parseSpec(type: type, body: body) else { continue }
            let help = body["help"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            controls.append(PropertyControl(
                name: name,
                spec: spec,
                help: (help?.isEmpty == false) ? help : nil
            ))
        }
        return controls
    }

    static func load(folder: URL) -> [PropertyControl] {
        let url = folder.appendingPathComponent(PackFormat.propertiesFile)
        guard let json = try? JSONValue.load(from: url) else { return [] }
        return parse(json)
    }

    private static func parseSpec(type: String, body: [String: JSONValue]) -> ControlSpec? {
        let text = body["text"]?.stringValue ?? ""

        switch type {
        case "slider":
            let min = body["min"]?.doubleValue ?? 0
            let max = body["max"]?.doubleValue ?? 1
            let step = body["step"]?.doubleValue ?? 0.01
            let value = body["value"]?.doubleValue ?? min
            return .slider(text: text, min: min, max: max, step: step, value: value)

        case "textbox":
            return .textbox(text: text, value: body["value"]?.stringValue ?? "")

        case "dropdown":
            let items = (body["items"]?.arrayValue ?? []).compactMap { item -> String? in
                item.stringValue ?? item.doubleValue.map { String(format: "%g", $0) }
            }
            return .dropdown(text: text, items: items, value: body["value"]?.intValue ?? 0)

        case "folderDropdown":
            return .folderDropdown(
                text: text,
                filter: body["filter"]?.stringValue ?? "*.*",
                folder: body["folder"]?.stringValue ?? "",
                value: body["value"]?.stringValue ?? ""
            )

        case "button":
            return .button(text: text, value: body["value"]?.stringValue ?? text)

        case "label":
            return .label(text: text)

        case "color":
            return .color(text: text, value: body["value"]?.stringValue ?? "#FFFFFF")

        case "checkbox":
            return .checkbox(text: text, value: body["value"]?.boolValue ?? false)

        default:
            return nil
        }
    }

    /// Values pushed on load, as `(name, value)` pairs for the page-side
    /// property listener.
    ///
    /// `folderDropdown` is special-cased: the value is sent only if the file
    /// exists under the pack's root folder, otherwise `null`.
    static func bridgeBindings(for controls: [PropertyControl], rootFolder: URL) -> [(name: String, value: JSONValue)] {
        controls.compactMap { control in
            switch control.spec {
            case .button, .label:
                return nil

            case .slider(_, _, _, _, let value):
                return (control.name, .number(value))

            case .textbox(_, let value):
                return (control.name, .string(value))

            case .dropdown(_, _, let value):
                return (control.name, .number(Double(value)))

            case .checkbox(_, let value):
                return (control.name, .bool(value))

            case .color(_, let value):
                return (control.name, .string(value))

            case .folderDropdown(_, _, let folder, let value):
                let candidate = rootFolder
                    .appendingPathComponent(folder)
                    .appendingPathComponent(value)
                let exists = value.isEmpty
                    ? false
                    : FileManager.default.fileExists(atPath: candidate.path)
                return (control.name, exists ? .string(value) : .null)
            }
        }
    }

    /// Files a `folderDropdown` offers, filtered by its wildcard pattern.
    ///
    /// `filter` is a `|`-separated (or `;`-separated) list of wildcards such as
    /// `"*.jpg|*.png"`. An empty filter lists everything.
    static func folderOptions(folder: URL, filter: String) -> [String] {
        let patterns = filter
            .split(whereSeparator: { $0 == "|" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }

        func matches(_ name: String) -> Bool {
            guard !patterns.isEmpty else { return true }
            let lower = name.lowercased()
            return patterns.contains { pattern in
                guard pattern.contains("*") else { return lower == pattern }
                let escaped = NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: ".*")
                return lower.range(of: "^\(escaped)$", options: .regularExpression) != nil
            }
        }

        return names
            .filter { !$0.hasPrefix(".") && matches($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
