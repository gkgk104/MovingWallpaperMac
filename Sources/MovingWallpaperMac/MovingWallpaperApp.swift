import AppKit
import SwiftUI

@main
struct MovingWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Moving Wallpaper", id: "main") {
            ContentView(model: model)
                .frame(
                    minWidth: 1040,
                    idealWidth: 1120,
                    maxWidth: .infinity,
                    minHeight: 520,
                    idealHeight: 560,
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

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }

    private static func isMainControlWindow(_ window: NSWindow) -> Bool {
        guard !(window is WallpaperWindow) else {
            return false
        }

        return window.title == "Moving Wallpaper" && window.canBecomeKey
    }
}
