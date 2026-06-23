import AppKit
import Combine
import Darwin
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
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let hiddenLaunchArguments: Set<String> = [
            "--motiondock-start-hidden",
            "--motiondock-login-item",
            "--start-hidden",
            "--background",
            "-background",
            "-hide"
        ]

        let hasHiddenLaunchArgument = arguments.contains { argument in
            hiddenLaunchArguments.contains(argument)
        }
        let hasHiddenLaunchEnvironment = [
            "MOTIONDOCK_START_HIDDEN",
            "MOTIONDOCK_LOGIN_ITEM"
        ].contains { key in
            guard let value = environment[key]?.lowercased() else {
                return false
            }
            return ["1", "true", "yes"].contains(value)
        }

        let shouldStartHidden = hasHiddenLaunchArgument || hasHiddenLaunchEnvironment
        let reason: String
        if hasHiddenLaunchArgument {
            reason = "explicit launch argument"
        } else if hasHiddenLaunchEnvironment {
            reason = "explicit launch environment"
        } else {
            reason = "normal launch"
        }

        NSLog(
            "[MotionDock Launch] shouldStartHidden=%@ reason=%@ startAtLoginEnabled=%@ arguments=%@",
            shouldStartHidden ? "true" : "false",
            reason,
            model.startAtLoginEnabled ? "true" : "false",
            arguments.joined(separator: " ")
        )
        return shouldStartHidden
    }
}

@MainActor
enum MotionDockDockVisibility {
    static func apply(showInDock: Bool, activateMainWindow: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        guard showInDock, activateMainWindow else {
            return
        }

        MainWindowRegistry.shared.restoreMainWindow(in: NSApp)
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
    static weak var shared: AppDelegate?

    private static let openExistingInstanceNotification = Notification.Name("com.motiondock.app.openExistingInstance")

    private var didPrepareForFullQuit = false
    private var isTerminatingDuplicateInstance = false
    private var quitFallbackWorkItem: DispatchWorkItem?
    private var pendingCallbackURLs: [URL] = []

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfDuplicateInstanceIsRunning() {
            return
        }

        NSApp.disableRelaunchOnLogin()
        MotionDockDockVisibility.apply(showInDock: AppModel.shared.showInDock, activateMainWindow: false)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openExistingInstance(_:)),
            name: Self.openExistingInstanceNotification,
            object: nil
        )

        MainWindowRegistry.shared.startsHidden = LaunchContext.shouldStartHidden
        MotionDockStatusItemController.shared.configure(model: AppModel.shared)
        AppModel.shared.restoreLastWallpaperOnLaunch()

        DispatchQueue.main.async {
            NSLog(
                "[MotionDock Launch] didFinishLaunching applying initial window state shouldStartHidden=%@",
                LaunchContext.shouldStartHidden ? "true" : "false"
            )
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
        if isTerminatingDuplicateInstance {
            return .terminateNow
        }

        prepareForFullQuit()
        scheduleQuitFallback()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSLog(
            "[MotionDock Launch] applicationShouldHandleReopen hasVisibleWindows=%@",
            flag ? "true" : "false"
        )
        MainWindowRegistry.shared.restoreMainWindow(in: sender)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleCallbackURLs(urls)
    }

    func quitFromMenu() {
        prepareForFullQuit()
        NSApp.terminate(nil)
        scheduleQuitFallback()
    }

    func applicationWillTerminate(_ notification: Notification) {
        quitFallbackWorkItem?.cancel()
        quitFallbackWorkItem = nil
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func prepareForFullQuit() {
        guard !didPrepareForFullQuit else {
            return
        }

        didPrepareForFullQuit = true
        AppModel.shared.stopForQuit()
        MotionDockStatusItemController.shared.removeStatusItem()
    }

    private func scheduleQuitFallback() {
        guard quitFallbackWorkItem == nil else {
            return
        }

        let fallback = DispatchWorkItem {
            exit(EXIT_SUCCESS)
        }
        quitFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: fallback)
    }

    private func terminateIfDuplicateInstanceIsRunning() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.motiondock.app"
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
            userInfo: notificationUserInfo(for: pendingCallbackURLs),
            deliverImmediately: true
        )
        existingInstance.activate(options: [.activateIgnoringOtherApps])
        isTerminatingDuplicateInstance = true
        NSApp.terminate(nil)
        return true
    }

    @objc private func openExistingInstance(_ notification: Notification) {
        NSLog("[MotionDock Launch] openExistingInstance notification received")
        if let rawURLs = notification.userInfo?["urls"] as? [String] {
            handleCallbackURLs(rawURLs.compactMap(URL.init(string:)))
        }
        MainWindowRegistry.shared.restoreMainWindow(in: NSApplication.shared)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL)
        else {
            NSLog("[MotionDock OAuth] received URL event but no valid URL was present")
            return
        }

        NSLog("[MotionDock OAuth] received URL event: %@", url.absoluteString)
        pendingCallbackURLs.append(url)
        handleCallbackURLs([url])
    }

    private func handleCallbackURLs(_ urls: [URL]) {
        urls.forEach { url in
            AppModel.shared.handleAuthCallbackURL(url)
        }
    }

    private func notificationUserInfo(for urls: [URL]) -> [String: Any]? {
        let rawURLs = urls.map(\.absoluteString)
        return rawURLs.isEmpty ? nil : ["urls": rawURLs]
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

        NSLog(
            "[MotionDock Window] registered main window startsHidden=%@ isVisible=%@",
            startsHidden ? "true" : "false",
            window.isVisible ? "true" : "false"
        )
        if startsHidden {
            NSLog("[MotionDock Window] ordering out main window for explicit hidden launch")
            window.orderOut(nil)
        }
    }

    func hideMainWindow(in application: NSApplication) {
        NSLog("[MotionDock Window] hideMainWindow requested")
        application.windows
            .filter(Self.isMainControlWindow)
            .forEach { $0.orderOut(nil) }
    }

    func restoreMainWindow(in application: NSApplication) {
        NSLog("[MotionDock Window] restoreMainWindow requested")
        application.unhide(nil)
        startsHidden = false

        guard let window = mainWindow ?? application.windows.first(where: Self.isMainControlWindow) else {
            NSLog("[MotionDock Window] no registered main window yet; activating app")
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
        if sender.styleMask.contains(.fullScreen) {
            NSLog("[MotionDock Window] red close requested in fullscreen; exiting fullscreen only")
            sender.toggleFullScreen(nil)
        } else {
            NSLog("[MotionDock Window] red close requested in normal window mode; hiding main window")
            hideMainWindow(sender)
        }
        return false
    }

    private func hideMainWindow(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderOut(nil)
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
        if let appDelegate = AppDelegate.shared ?? NSApp.delegate as? AppDelegate {
            appDelegate.quitFromMenu()
            return
        }

        AppModel.shared.stopForQuit()
        removeStatusItem()
        exit(EXIT_SUCCESS)
    }

    private func updateMenuState() {
        guard let model else {
            return
        }
        startItem.isEnabled = model.canStart
        stopItem.isEnabled = model.isRunning
        restoreItem.isEnabled = model.canRestoreLastWallpaper
    }

    func removeStatusItem() {
        cancellable = nil

        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
