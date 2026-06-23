import AppKit
import CoreGraphics
import SwiftUI

@MainActor
protocol WallpaperPlaybackControlling: AnyObject {
    func setPaused(_ paused: Bool)
    func setMuted(_ muted: Bool)
    func setFillMode(_ fillMode: VideoFillMode)
    func recoverAfterSystemTransition(isPaused: Bool)
}

extension WallpaperPlaybackControlling {
    func recoverAfterSystemTransition(isPaused: Bool) {
        setPaused(isPaused)
    }
}

@MainActor
final class WallpaperManager {
    private var windows: [WallpaperWindow] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var recoveryWorkItems: [DispatchWorkItem] = []
    private var configuration: WallpaperConfiguration?
    private var isSuspended = false

    func start(with configuration: WallpaperConfiguration) throws {
        stop()
        self.configuration = configuration
        windows = try targetScreens(for: configuration.displayMode).map { screen in
            try makeWindow(for: screen, configuration: configuration)
        }
        installSystemTransitionObservers()
        scheduleWindowRecovery(reason: "wallpaper start")
    }

    func stop() {
        recoveryWorkItems.forEach { $0.cancel() }
        recoveryWorkItems.removeAll()
        observers.forEach { center, observer in
            center.removeObserver(observer)
        }
        observers.removeAll()

        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        configuration = nil
        isSuspended = false
    }

    func recoverAfterSystemTransition() {
        scheduleWindowRecovery(reason: "external recovery request")
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
            recoverWallpaperWindows(reason: "resume while already active")
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
        recoverWallpaperWindows(reason: "resume")
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

    private func installSystemTransitionObservers() {
        let defaultCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        addObserver(
            center: defaultCenter,
            name: NSApplication.didChangeScreenParametersNotification,
            rebuild: true
        )

        [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ].forEach { name in
            addObserver(center: workspaceCenter, name: name, rebuild: false)
        }
    }

    private func addObserver(center: NotificationCenter, name: Notification.Name, rebuild: Bool) {
        let observer = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.name.rawValue
            Task { @MainActor in
                if rebuild {
                    self?.rebuildForCurrentScreens()
                }
                self?.scheduleWindowRecovery(reason: reason)
            }
        }
        observers.append((center, observer))
    }

    private func scheduleWindowRecovery(reason: String) {
        recoveryWorkItems.forEach { $0.cancel() }
        recoveryWorkItems.removeAll()

        for delay in [0.2, 1.0] {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.recoverWallpaperWindows(reason: reason)
                }
            }
            recoveryWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func recoverWallpaperWindows(reason: String) {
        guard let configuration else {
            return
        }

        let screens = targetScreens(for: configuration.displayMode)
        guard !screens.isEmpty else {
            windows.forEach { $0.orderOut(nil) }
            return
        }

        guard !(isSuspended && windows.isEmpty) else {
            return
        }

        guard windows.count == screens.count else {
            rebuildForCurrentScreens()
            return
        }

        for (window, screen) in zip(windows, screens) {
            window.applyDesktopPlacement(on: screen)
            window.orderFrontRegardless()

            if let playbackView = window.contentView as? WallpaperPlaybackControlling {
                playbackView.recoverAfterSystemTransition(isPaused: isSuspended)
            }
        }

        NSLog("[MotionDock Wallpaper] recovered wallpaper windows after %@", reason)
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
        guard !NSScreen.screens.isEmpty else {
            return []
        }

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

        applyDesktopPlacement(on: screen)
    }

    func applyDesktopPlacement(on screen: NSScreen) {
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
        displaysWhenScreenProfileChanges = true
        canHide = false
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
