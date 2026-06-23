import AppKit

enum GIFWallpaperError: LocalizedError {
    case unreadableGIF(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableGIF(let url):
            "\(url.lastPathComponent)을 GIF 배경으로 읽을 수 없습니다."
        }
    }
}

final class GIFWallpaperView: NSView, WallpaperPlaybackControlling {
    private let imageView = NSImageView()
    private let imageSize: CGSize
    private var fillMode: VideoFillMode
    private var isPaused = false

    init(url: URL, fillMode: VideoFillMode) throws {
        guard let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 else {
            throw GIFWallpaperError.unreadableGIF(url)
        }

        imageSize = image.size
        self.fillMode = fillMode
        super.init(frame: .zero)

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        imageView.image = image
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageView.frame = imageFrame(for: bounds.size)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        imageView.animates = !paused
    }

    func setMuted(_ muted: Bool) {}

    func setFillMode(_ fillMode: VideoFillMode) {
        self.fillMode = fillMode
        needsLayout = true
    }

    func recoverAfterSystemTransition(isPaused: Bool) {
        self.isPaused = isPaused
        imageView.animates = false
        imageView.frame = imageFrame(for: bounds.size)
        imageView.animates = !isPaused
        needsLayout = true
    }

    private func imageFrame(for containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let scale: CGFloat

        switch fillMode {
        case .cover:
            scale = containerAspect > imageAspect
                ? containerSize.width / imageSize.width
                : containerSize.height / imageSize.height
        case .fit:
            scale = containerAspect > imageAspect
                ? containerSize.height / imageSize.height
                : containerSize.width / imageSize.width
        }

        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - scaledSize.width) / 2,
            y: (containerSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}
