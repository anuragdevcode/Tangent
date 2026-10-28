import AVFoundation
import CoreMedia
import Foundation

/// Chooses which decoder plays a video file.
///
/// AVFoundation is preferred: it uses VideoToolbox hardware decoding and is
/// what most macOS video wallpapers (H.264/HEVC) are encoded for. libmpv is
/// used when the container or codec is outside AVFoundation's reach — VP9/WebM,
/// AV1, Matroska, Ogg and Flash containers.
enum VideoBackend: Equatable {
    case avFoundation
    case mpv
}

enum VideoRouting {

    /// Containers AVFoundation cannot open reliably, independent of codec.
    static let mpvExtensions: Set<String> = [
        "webm", "mkv", "avi", "ogv", "flv", "m2ts", "ts",
    ]

    /// Video codecs that need libmpv even inside an MP4/MOV container.
    static let mpvCodecs: Set<String> = ["vp08", "vp09", "av01"]

    static func backend(for url: URL) -> VideoBackend {
        let fileExtension = url.pathExtension.lowercased()
        if mpvExtensions.contains(fileExtension) { return .mpv }

        if let codec = codecFourCC(for: url), mpvCodecs.contains(codec) {
            return .mpv
        }
        return .avFoundation
    }

    /// FourCC of the first video track (`avc1`, `hvc1`, `vp09`, `av01`...), or
    /// nil when the container/metadata cannot be read. This only parses
    /// metadata; it does not decode a frame.
    static func codecFourCC(for url: URL) -> String? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let description = track.formatDescriptions.first
        else { return nil }

        guard CFGetTypeID(description as CFTypeRef) == CMFormatDescriptionGetTypeID() else {
            return nil
        }
        let format = description as! CMFormatDescription
        let code = CMFormatDescriptionGetMediaSubType(format)
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii)
    }
}
