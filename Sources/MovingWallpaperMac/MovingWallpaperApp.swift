import AppKit
import SwiftUI

@main
struct MovingWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("MotionDock", id: "main") {
            ContentView(model: model)
                .frame(
                    minWidth: 920,
                    idealWidth: 1180,
                    maxWidth: .infinity,
                    minHeight: 640,
                    idealHeight: 720,
                    maxHeight: .infinity
                )
                .background(MainWindowAccessor())
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowRegistry.shared.restoreMainWindow(in: sender)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainWindowRegistry.shared.restoreMainWindowIfNeeded(in: NSApplication.shared)
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            MainWindowRegistry.shared.registerMainWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            MainWindowRegistry.shared.registerMainWindow(from: nsView)
        }
    }
}

@MainActor
private final class MainWindowRegistry {
    static let shared = MainWindowRegistry()

    private weak var mainWindow: NSWindow?

    private init() {}

    func registerMainWindow(from view: NSView) {
        guard let window = view.window, Self.isMainControlWindow(window) else {
            return
        }

        mainWindow = window
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 640)
        constrainToVisibleScreen(window)
    }

    func restoreMainWindowIfNeeded(in application: NSApplication) {
        let hasVisibleMainWindow = application.windows.contains { window in
            Self.isMainControlWindow(window) && window.isVisible && !window.isMiniaturized
        }

        guard !hasVisibleMainWindow else {
            return
        }

        restoreMainWindow(in: application)
    }

    func restoreMainWindow(in application: NSApplication) {
        application.unhide(nil)

        guard let window = mainWindow ?? application.windows.first(where: Self.isMainControlWindow) else {
            application.activate(ignoringOtherApps: true)
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        constrainToVisibleScreen(window)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }

    private static func isMainControlWindow(_ window: NSWindow) -> Bool {
        guard !(window is WallpaperWindow) else {
            return false
        }

        return window.title == "MotionDock" && window.canBecomeKey
    }

    private func constrainToVisibleScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        var frame = window.frame

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
        }

        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
        }

        if frame.minX < visibleFrame.minX || frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.midX - frame.width / 2
        }

        if frame.minY < visibleFrame.minY || frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.midY - frame.height / 2
        }

        window.setFrame(frame, display: true)
    }
}
