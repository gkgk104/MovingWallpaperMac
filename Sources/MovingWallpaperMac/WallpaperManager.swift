import AppKit
import CoreGraphics
import SwiftUI

@MainActor
protocol WallpaperPlaybackControlling: AnyObject {
    func setPaused(_ paused: Bool)
    func setMuted(_ muted: Bool)
    func setFillMode(_ fillMode: VideoFillMode)
}

@MainActor
final class WallpaperManager {
    private var windows: [WallpaperWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var configuration: WallpaperConfiguration?
    private var isSuspended = false

    func start(with configuration: WallpaperConfiguration) throws {
        stop()
        self.configuration = configuration
        windows = try targetScreens(for: configuration.displayMode).map { screen in
            try makeWindow(for: screen, configuration: configuration)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildForCurrentScreens()
            }
        }
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        configuration = nil
        isSuspended = false
    }

    func updatePlaybackSettings(muted: Bool, fillMode: VideoFillMode) {
        windows.compactMap { $0.contentView as? WallpaperPlaybackControlling }.forEach { view in
            view.setMuted(muted)
            view.setFillMode(fillMode)
        }
    }

    func suspend(releaseResources: Bool) {
        guard !isSuspended else {
            return
        }

        if releaseResources {
            windows.forEach { window in
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            windows.removeAll()
        } else {
            windows.compactMap { $0.contentView as? WallpaperPlaybackControlling }.forEach { view in
                view.setPaused(true)
            }
        }

        isSuspended = true
    }

    func resume() {
        guard isSuspended else {
            return
        }

        if windows.isEmpty, let configuration {
            do {
                windows = try targetScreens(for: configuration.displayMode).map { screen in
                    try makeWindow(for: screen, configuration: configuration)
                }
            } catch {
                windows.removeAll()
            }
        } else {
            windows.compactMap { $0.contentView as? WallpaperPlaybackControlling }.forEach { view in
                view.setPaused(false)
            }
        }

        isSuspended = false
    }

    private func rebuildForCurrentScreens() {
        guard let configuration else {
            return
        }

        do {
            try start(with: configuration)
        } catch {
            stop()
        }
    }

    private func makeWindow(for screen: NSScreen, configuration: WallpaperConfiguration) throws -> WallpaperWindow {
        let window = WallpaperWindow(screen: screen)

        switch configuration.source {
        case .motion(let scene, let palette):
            window.contentView = MotionWallpaperHostView(
                scene: scene,
                palette: palette,
                performanceProfile: configuration.performanceProfile
            )
        case .video(let url):
            window.contentView = try VideoWallpaperView(
                url: url,
                muted: configuration.muted,
                fillMode: configuration.fillMode
            )
        case .gif(let url):
            window.contentView = try GIFWallpaperView(
                url: url,
                fillMode: configuration.fillMode
            )
        case .web(let url):
            window.contentView = WebWallpaperView(url: url)
        }

        window.orderFrontRegardless()
        return window
    }

    private func targetScreens(for displayMode: DisplayMode) -> [NSScreen] {
        switch displayMode {
        case .allDisplays:
            return NSScreen.screens
        case .mainDisplay:
            return [NSScreen.main ?? NSScreen.screens[0]]
        }
    }
}

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let desktopIconLevel = CGWindowLevelForKey(.desktopIconWindow)
        level = NSWindow.Level(rawValue: Int(desktopIconLevel) - 1)
        backgroundColor = .black
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        hasShadow = false
        ignoresMouseEvents = true
        isOpaque = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
