import AppKit
import Combine
import SwiftUI

private enum MotionDockDefaultsMigration {
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateLegacyDefaultsToMotionDock"

        guard defaults.object(forKey: migrationKey) == nil else {
            return
        }

        defer {
            defaults.set(true, forKey: migrationKey)
        }

        for legacyDomainName in ["local.codex.motiondeck"] {
            guard let legacyDomain = UserDefaults.standard.persistentDomain(forName: legacyDomainName) else {
                continue
            }

            for (key, value) in legacyDomain {
                guard defaults.object(forKey: key) == nil else {
                    continue
                }
                guard !key.hasPrefix("NSWindow Frame") else {
                    continue
                }
                defaults.set(value, forKey: key)
            }
        }
    }
}

@MainActor
private enum LaunchContext {
    static var shouldStartHidden = false

    static func resolveShouldStartHidden(model: AppModel) -> Bool {
        let wasLaunchedByFinderOrOpen = ProcessInfo.processInfo.arguments.contains { argument in
            argument.hasPrefix("-psn_")
        }
        return model.startAtLoginEnabled && !wasLaunchedByFinderOrOpen
    }
}

@main
struct MovingWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        MotionDockDefaultsMigration.migrateIfNeeded()
        let sharedModel = AppModel.shared
        LaunchContext.shouldStartHidden = LaunchContext.resolveShouldStartHidden(model: sharedModel)
        _model = StateObject(wrappedValue: sharedModel)
    }

    var body: some Scene {
        Window("MotionDock", id: "main") {
            ContentView(model: model)
                .frame(
                    minWidth: MotionDockLayout.minimumWindowWidth,
                    idealWidth: MotionDockLayout.idealWindowWidth,
                    maxWidth: .infinity,
                    minHeight: MotionDockLayout.minimumWindowHeight,
                    idealHeight: MotionDockLayout.idealWindowHeight,
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
    private static let openExistingInstanceNotification = Notification.Name("local.codex.motiondock.openExistingInstance")

    private var isQuittingFromMenu = false
    private var isTerminatingDuplicateInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfDuplicateInstanceIsRunning() {
            return
        }

        NSApp.disableRelaunchOnLogin()
        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openExistingInstance),
            name: Self.openExistingInstanceNotification,
            object: nil
        )

        MainWindowRegistry.shared.startsHidden = LaunchContext.shouldStartHidden
        MotionDockStatusItemController.shared.configure(model: AppModel.shared)
        AppModel.shared.restoreLastWallpaperOnLaunch()

        DispatchQueue.main.async {
            if LaunchContext.shouldStartHidden {
                MainWindowRegistry.shared.hideMainWindow(in: NSApplication.shared)
            } else {
                MainWindowRegistry.shared.restoreMainWindow(in: NSApplication.shared)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (isQuittingFromMenu || isTerminatingDuplicateInstance) ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowRegistry.shared.restoreMainWindow(in: sender)
        return true
    }

    func quitFromMenu() {
        isQuittingFromMenu = true
        AppModel.shared.stopForQuit()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func terminateIfDuplicateInstanceIsRunning() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "local.codex.motiondock"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { application in
                application.processIdentifier != currentPID && !application.isTerminated
            }

        guard let existingInstance else {
            return false
        }

        DistributedNotificationCenter.default().postNotificationName(
            Self.openExistingInstanceNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        existingInstance.activate(options: [.activateIgnoringOtherApps])
        isTerminatingDuplicateInstance = true
        NSApp.terminate(nil)
        return true
    }

    @objc private func openExistingInstance() {
        MainWindowRegistry.shared.restoreMainWindow(in: NSApplication.shared)
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
    var startsHidden = false

    private init() {}

    func registerMainWindow(from view: NSView) {
        guard let window = view.window, Self.isMainControlWindow(window) else {
            return
        }

        mainWindow = window
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = MainWindowCloseDelegate.shared
        window.minSize = NSSize(
            width: MotionDockLayout.minimumWindowWidth,
            height: MotionDockLayout.minimumWindowHeight
        )
        constrainToVisibleScreen(window)

        if startsHidden {
            window.orderOut(nil)
        }
    }

    func hideMainWindow(in application: NSApplication) {
        application.windows
            .filter(Self.isMainControlWindow)
            .forEach { $0.orderOut(nil) }
    }

    func restoreMainWindow(in application: NSApplication) {
        application.unhide(nil)
        startsHidden = false

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
        let fillsVisibleScreen = frame.width >= visibleFrame.width - 2 && frame.height >= visibleFrame.height - 2

        if fillsVisibleScreen {
            frame.size.width = min(MotionDockLayout.idealWindowWidth, visibleFrame.width)
            frame.size.height = min(MotionDockLayout.idealWindowHeight, visibleFrame.height)
        }

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

@MainActor
private final class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowCloseDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
private final class MotionDockStatusItemController: NSObject, NSMenuDelegate {
    static let shared = MotionDockStatusItemController()

    private var statusItem: NSStatusItem?
    private weak var model: AppModel?
    private var cancellable: AnyCancellable?

    private let openItem = NSMenuItem(title: "Open MotionDock", action: #selector(openMotionDock), keyEquivalent: "")
    private let startItem = NSMenuItem(title: "Start Wallpaper", action: #selector(startWallpaper), keyEquivalent: "")
    private let stopItem = NSMenuItem(title: "Stop Wallpaper", action: #selector(stopWallpaper), keyEquivalent: "")
    private let restoreItem = NSMenuItem(title: "Restore Last Wallpaper", action: #selector(restoreLastWallpaper), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit MotionDock", action: #selector(quitMotionDock), keyEquivalent: "q")

    func configure(model: AppModel) {
        self.model = model

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        item.button?.image = MotionDockBrand.statusBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        [openItem, startItem, stopItem, restoreItem, settingsItem, quitItem].forEach { menuItem in
            menuItem.target = self
        }
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(restoreItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu

        cancellable = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                Task { @MainActor in
                    self?.updateMenuState()
                }
            }
        }
        updateMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }

    @objc private func openMotionDock() {
        MainWindowRegistry.shared.restoreMainWindow(in: NSApplication.shared)
    }

    @objc private func startWallpaper() {
        model?.start()
    }

    @objc private func stopWallpaper() {
        model?.stop()
    }

    @objc private func restoreLastWallpaper() {
        model?.restoreLastWallpaper()
    }

    @objc private func openSettings() {
        model?.requestSettings()
        MainWindowRegistry.shared.restoreMainWindow(in: NSApplication.shared)
    }

    @objc private func quitMotionDock() {
        (NSApp.delegate as? AppDelegate)?.quitFromMenu()
    }

    private func updateMenuState() {
        guard let model else {
            return
        }
        startItem.isEnabled = model.canStart
        stopItem.isEnabled = model.isRunning
        restoreItem.isEnabled = model.canRestoreLastWallpaper
    }
}
