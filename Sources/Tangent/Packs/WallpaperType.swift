import Foundation

/// Wallpaper kinds recognised by the pack format, including an `unknown` case
/// so a pack written for a newer format still loads instead of failing to
/// decode.
enum WallpaperType: Equatable {
    case app
    case web
    case webaudio
    case url
    case bizhawk
    case unity
    case godot
    case video
    case gif
    case unityaudio
    case videostream
    case picture
    case unknown(String)

    /// The pack format serialises the enum member name in lowercase.
    init(raw: String) {
        switch raw.lowercased() {
        case "app": self = .app
        case "web": self = .web
        case "webaudio": self = .webaudio
        case "url": self = .url
        case "bizhawk": self = .bizhawk
        case "unity": self = .unity
        case "godot": self = .godot
        case "video": self = .video
        case "gif": self = .gif
        case "unityaudio": self = .unityaudio
        case "videostream": self = .videostream
        case "picture": self = .picture
        default: self = .unknown(raw)
        }
    }

    var rawValue: String {
        switch self {
        case .app: return "app"
        case .web: return "web"
        case .webaudio: return "webaudio"
        case .url: return "url"
        case .bizhawk: return "bizhawk"
        case .unity: return "unity"
        case .godot: return "godot"
        case .video: return "video"
        case .gif: return "gif"
        case .unityaudio: return "unityaudio"
        case .videostream: return "videostream"
        case .picture: return "picture"
        case .unknown(let value): return value
        }
    }

    /// Types this build can render.
    var isSupported: Bool {
        switch self {
        case .web, .webaudio, .url, .video, .gif, .picture:
            return true
        case .app, .bizhawk, .unity, .unityaudio, .godot:
            return false
        case .videostream:
            // HLS/remote stream: AVPlayer can do it, but not yet wired up here.
            return false
        case .unknown:
            return false
        }
    }

    /// Plain-language reason, shown in the library UI instead of silently
    /// dropping an item or failing at apply time.
    var unsupportedReason: String? {
        switch self {
        case .app, .unity, .unityaudio, .godot:
            return "Runs a Windows application and reparents its window. macOS cannot embed another app's window in the desktop."
        case .bizhawk:
            return "BizHawk emulator integration is Windows-only."
        case .videostream:
            return "Remote/HLS video streams are not wired up in this build."
        case .unknown:
            return "This wallpaper type is newer than this build."
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .app: return "Application"
        case .web: return "Web"
        case .webaudio: return "Web (audio)"
        case .url: return "Web URL"
        case .bizhawk: return "Emulator"
        case .unity: return "Unity"
        case .godot: return "Godot"
        case .video: return "Video"
        case .gif: return "GIF"
        case .unityaudio: return "Unity audio"
        case .videostream: return "Stream"
        case .picture: return "Picture"
        case .unknown(let value): return value
        }
    }
}
