import AppKit
import AVFoundation

enum VideoWallpaperError: LocalizedError {
    case unreadableMovie(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableMovie(let url):
            "\(url.lastPathComponent)을 재생할 수 없습니다."
        }
    }
}

final class VideoWallpaperView: NSView, WallpaperPlaybackControlling {
    private let player = AVQueuePlayer()
    private let playerLayer: AVPlayerLayer
    private var looper: AVPlayerLooper?

    init(url: URL, muted: Bool, fillMode: VideoFillMode) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw VideoWallpaperError.unreadableMovie(url)
        }

        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor

        playerLayer.videoGravity = fillMode.videoGravity
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        player.actionAtItemEnd = .none
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func setPaused(_ paused: Bool) {
        if paused {
            player.pause()
        } else {
            player.play()
        }
    }

    func setFillMode(_ fillMode: VideoFillMode) {
        playerLayer.videoGravity = fillMode.videoGravity
    }

    deinit {
        player.pause()
    }
}
