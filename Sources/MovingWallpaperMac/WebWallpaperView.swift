import AppKit
import WebKit

final class WebWallpaperView: NSView, WallpaperPlaybackControlling {
    private let webView: WKWebView

    init(url: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        webView.allowsMagnification = false
        addSubview(webView)
        webView.load(URLRequest(url: url))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    func setPaused(_ paused: Bool) {
        isHidden = paused
        let command = paused
            ? "document.querySelectorAll('video,audio').forEach((media) => media.pause())"
            : "document.querySelectorAll('video,audio').forEach((media) => media.play && media.play().catch(() => {}))"
        webView.evaluateJavaScript(command)
    }

    func setMuted(_ muted: Bool) {
        let command = "document.querySelectorAll('video,audio').forEach((media) => media.muted = \(muted ? "true" : "false"))"
        webView.evaluateJavaScript(command)
    }

    func setFillMode(_ fillMode: VideoFillMode) {}
}
