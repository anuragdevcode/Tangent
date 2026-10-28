import AppKit
import AVFoundation

/// Produces library thumbnails.
///
/// Packs may ship a `Thumbnail` image, but user-made packs often omit it. For
/// those a frame is extracted from the video instead of showing a blank tile.
final class ThumbnailProvider {

    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let size = CGSize(width: 480, height: 270)

    private init() {
        cache.countLimit = 64
    }

    func thumbnail(for pack: Pack) async -> NSImage? {
        let key = pack.id as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = await load(pack: pack)
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private func load(pack: Pack) async -> NSImage? {
        if let thumbnailURL = pack.thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
            return image
        }

        switch pack.info.type {
        case .video, .videostream:
            if let previewURL = pack.previewURL, let image = await videoFrame(from: previewURL) {
                return image
            }
            if let entry = pack.entryURL, !pack.isRemoteEntry {
                return await videoFrame(from: entry)
            }
            return nil

        case .gif, .picture:
            if let entry = pack.entryURL, !pack.isRemoteEntry {
                return NSImage(contentsOf: entry)
            }
            return nil

        default:
            return nil
        }
    }

    private func videoFrame(from url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        // Seek slightly in: the first frame of many packs is a black fade-in.
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let (cgImage, _) = try? await generator.image(at: time) else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }
}
