import AVFoundation
import AppKit

extension Notification.Name {
    /// Posted when a video file exists but the system cannot decode it.
    static let tangentVideoUnplayable = Notification.Name("tangent.video.unplayable")
}

/// Video wallpaper backend.
///
/// On Windows this is WMF / libmpv / VLC / WebView2 depending on the build.
/// On Apple Silicon the correct default is AVFoundation, which decodes
/// H.264/HEVC in hardware through VideoToolbox and costs almost no CPU or
/// battery. Formats AVFoundation cannot decode (VP9/WebM, AV1, Matroska) are
/// routed to `MPVWallpaper`; see `VideoRouting` and ARCHITECTURE.md.
final class VideoWallpaper: Wallpaper {
    let type: WallpaperType = .video
    let view: NSView
    private(set) var isLoaded = false

    private let player: AVQueuePlayer
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?

    init(url: URL, muted: Bool) {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        let item = AVPlayerItem(asset: asset)
        player = AVQueuePlayer()
        player.isMuted = muted
        player.actionAtItemEnd = .advance
        // A wallpaper must never stall on buffering heuristics.
        player.automaticallyWaitsToMinimizeStalling = false

        // AVPlayerLooper gives gapless looping without the seek-at-end gap
        // that a naive AVPlayer + seekToTime loop produces.
        looper = AVPlayerLooper(player: player, templateItem: item)

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor

        view = LayerHostView(hosting: playerLayer)
        isLoaded = true

        // Async, non-blocking validation so a bad codec surfaces as a real
        // message instead of a silent black desktop.
        Task.detached { [weak self] in
            guard self != nil else { return }
            let playable = (try? await asset.load(.isPlayable)) ?? false
            guard !playable else { return }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .tangentVideoUnplayable,
                    object: nil,
                    userInfo: ["path": url.path]
                )
            }
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func close() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        playerLayer.player = nil
        view.removeFromSuperview()
        isLoaded = false
    }
}
