import AppKit
import AVFoundation
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum MarketplaceThumbnailError: LocalizedError {
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Thumbnail image could not be encoded."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var libraryItems: [WallpaperLibraryItem] {
        didSet {
            saveLibrary()
        }
    }

    @Published var selectedItemID: String {
        didSet {
            UserDefaults.standard.set(selectedItemID, forKey: DefaultsKey.selectedItemID)
            guard !suppressAutomaticRestart else {
                return
            }
            scheduleRestartIfRunning()
        }
    }

    @Published var webURLDraft = ""
    @Published var marketplaceServerURLString: String {
        didSet {
            UserDefaults.standard.set(marketplaceServerURLString, forKey: DefaultsKey.marketplaceServerURLString)
        }
    }
    @Published private(set) var marketplaceItems: [MarketplaceItem] = []
    @Published private(set) var marketplaceIsLoading = false
    @Published private(set) var marketplaceBusyItemID: String?
    @Published var marketplaceMessage: String?
    @Published private(set) var discoverWallpapers: [DiscoverWallpaper] = []
    @Published private(set) var discoverIsLoading = false
    @Published private(set) var discoverBusyItemID: String?
    @Published private(set) var discoverLikeBusyItemIDs: Set<String> = []
    @Published private(set) var discoverReportBusyItemID: String?
    @Published private(set) var discoverUploadIsLoading = false
    @Published var discoverMessage: String?
    @Published private(set) var selectedDiscoverWallpaperID: String?
    @Published private(set) var myUploads: [DiscoverWallpaper] = []
    @Published private(set) var myUploadsIsLoading = false
    @Published private(set) var myUploadsBusyItemID: String?
    @Published var myUploadsMessage: String?
    @Published private(set) var authenticatedUser: MotionDockAuthenticatedUser?
    @Published private(set) var authIsLoading = false
    @Published var authMessage: String?
    @Published var profileDisplayNameDraft = ""
    @Published private(set) var profileDisplayNameIsSaving = false
    @Published var supabaseURLDraft: String
    @Published var supabaseAnonKeyDraft: String
    @Published var supabaseMarketplaceBucketDraft: String
    @Published var supabaseMarketplaceTableDraft: String
    @Published var supabaseConfigurationMessage: String?
    @Published var favoriteItemIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(favoriteItemIDs), forKey: DefaultsKey.favoriteItemIDs)
        }
    }

    @Published var playlistEnabled: Bool {
        didSet {
            UserDefaults.standard.set(playlistEnabled, forKey: DefaultsKey.playlistEnabled)
            schedule { $0.configurePlaylistTimer() }
        }
    }

    @Published var playlistIntervalMinutes: Double {
        didSet {
            UserDefaults.standard.set(playlistIntervalMinutes, forKey: DefaultsKey.playlistIntervalMinutes)
            schedule { $0.configurePlaylistTimer() }
        }
    }

    @Published var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: DefaultsKey.displayMode)
            scheduleRestartIfRunning()
        }
    }

    @Published var performanceProfile: PerformanceProfile {
        didSet {
            UserDefaults.standard.set(performanceProfile.rawValue, forKey: DefaultsKey.performanceProfile)
            scheduleRestartIfRunning()
        }
    }

    @Published var performancePolicy: PerformancePolicy {
        didSet {
            UserDefaults.standard.set(performancePolicy.rawValue, forKey: DefaultsKey.performancePolicy)
            schedule { $0.evaluatePerformancePolicy() }
        }
    }

    @Published var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: DefaultsKey.isMuted)
            schedule { $0.manager.updatePlaybackSettings(muted: $0.isMuted, fillMode: $0.fillMode) }
        }
    }

    @Published var fillMode: VideoFillMode {
        didSet {
            UserDefaults.standard.set(fillMode.rawValue, forKey: DefaultsKey.fillMode)
            schedule { $0.manager.updatePlaybackSettings(muted: $0.isMuted, fillMode: $0.fillMode) }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var isSuspended = false
    @Published var errorMessage: String?
    @Published private(set) var startAtLoginEnabled: Bool
    @Published private(set) var showInDock: Bool
    @Published var loginItemMessage: String?
    @Published private(set) var settingsRequestCounter = 0

    private let manager = WallpaperManager()
    private var authService = MotionDockSupabaseAuthService()
    private var playlistTimer: Timer?
    private var performanceTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var systemTransitionObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var systemTransitionRecoveryWorkItems: [DispatchWorkItem] = []
    private var suppressAutomaticRestart = false

    private enum MarketplaceUploadSource {
        case discover
        case settings
    }

    var canStart: Bool {
        guard let selectedItem else {
            return false
        }
        return isUsable(item: selectedItem)
    }

    var statusText: String {
        if isSuspended {
            return "성능 정책으로 대기"
        }
        return isRunning ? "실행 중" : "대기"
    }

    var selectedItem: WallpaperLibraryItem? {
        libraryItems.first { $0.id == selectedItemID } ?? libraryItems.first
    }

    var removableSelection: Bool {
        selectedItem?.isBuiltIn == false
    }

    var canRevealSelectedItem: Bool {
        selectedLocalFileURL != nil
    }

    var canRestoreLastWallpaper: Bool {
        UserDefaults.standard.data(forKey: DefaultsKey.lastWallpaperRecord) != nil
    }

    var isAuthenticated: Bool {
        authenticatedUser != nil
    }

    var authConfigurationMessage: String? {
        authService.configurationMessage
    }

    var isSupabaseConfigured: Bool {
        authService.isConfigured
    }

    var canSaveSupabaseConfiguration: Bool {
        !supabaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !supabaseAnonKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var supabaseConfigurationPath: String {
        MotionDockSupabaseConfiguration.applicationSupportConfigURL.path
    }

    var marketplaceBackendText: String {
        authService.marketplaceDescription
    }

    var selectedDiscoverWallpaper: DiscoverWallpaper? {
        guard let selectedDiscoverWallpaperID else {
            return nil
        }
        return discoverWallpapers.first { $0.id == selectedDiscoverWallpaperID }
    }

    var profileDisplayText: String {
        authenticatedUser?.displayName ?? "Sign in required"
    }

    var canSaveProfileDisplayName: Bool {
        guard let authenticatedUser else {
            return false
        }

        let draft = profileDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !draft.isEmpty
            && draft != authenticatedUser.displayName
            && !profileDisplayNameIsSaving
            && !authIsLoading
    }

    var defaultMarketplaceUploadDisplayName: String {
        if let displayName = authenticatedUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        if let email = authenticatedUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }
        return "Unknown"
    }

    init() {
        let defaults = UserDefaults.standard
        let loadedLibrary = Self.loadLibrary(from: defaults)
        libraryItems = loadedLibrary

        let fallbackID = loadedLibrary.first?.id ?? "motion-aurora"
        let savedSelectedItemID = defaults.string(forKey: DefaultsKey.selectedItemID) ?? fallbackID
        selectedItemID = loadedLibrary.contains { $0.id == savedSelectedItemID } ? savedSelectedItemID : fallbackID

        playlistEnabled = defaults.object(forKey: DefaultsKey.playlistEnabled) as? Bool ?? false
        playlistIntervalMinutes = defaults.object(forKey: DefaultsKey.playlistIntervalMinutes) as? Double ?? 10.0

        let savedDisplayMode = defaults.string(forKey: DefaultsKey.displayMode)
        displayMode = DisplayMode(rawValue: savedDisplayMode ?? "") ?? .allDisplays

        let savedPerformanceProfile = defaults.string(forKey: DefaultsKey.performanceProfile)
        performanceProfile = PerformanceProfile(rawValue: savedPerformanceProfile ?? "") ?? .balanced

        let savedPerformancePolicy = defaults.string(forKey: DefaultsKey.performancePolicy)
        performancePolicy = PerformancePolicy(rawValue: savedPerformancePolicy ?? "") ?? .pauseWhenCovered

        isMuted = defaults.object(forKey: DefaultsKey.isMuted) as? Bool ?? true

        let savedFillMode = defaults.string(forKey: DefaultsKey.fillMode)
        fillMode = VideoFillMode(rawValue: savedFillMode ?? "") ?? .cover

        marketplaceServerURLString = defaults.string(forKey: DefaultsKey.marketplaceServerURLString) ?? "http://127.0.0.1:8787"
        authenticatedUser = nil
        profileDisplayNameDraft = ""
        authMessage = nil
        let existingSupabaseConfiguration = try? MotionDockSupabaseConfiguration.load()
        supabaseURLDraft = existingSupabaseConfiguration?.url.absoluteString ?? ""
        supabaseAnonKeyDraft = existingSupabaseConfiguration?.anonKey ?? ""
        supabaseMarketplaceBucketDraft = existingSupabaseConfiguration?.marketplaceBucket ?? MotionDockSupabaseConfiguration.defaultMarketplaceBucket
        supabaseMarketplaceTableDraft = existingSupabaseConfiguration?.marketplaceTable ?? MotionDockSupabaseConfiguration.defaultMarketplaceTable
        supabaseConfigurationMessage = nil
        favoriteItemIDs = Set(defaults.stringArray(forKey: DefaultsKey.favoriteItemIDs) ?? [])
        startAtLoginEnabled = defaults.object(forKey: DefaultsKey.startAtLoginEnabled) as? Bool
            ?? (SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval)
        showInDock = defaults.object(forKey: DefaultsKey.showInDock) as? Bool ?? false

        NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.evaluatePerformancePolicy()
                }
            }
            .store(in: &cancellables)

        installSystemTransitionObservers()

        Task { @MainActor in
            await restoreAuthSessionNow()
        }
    }

    var canUploadSelectedItem: Bool {
        guard let selectedItem, selectedItem.isBuiltIn == false else {
            return false
        }
        guard selectedItem.kind == .video, let path = selectedItem.videoPath else {
            return false
        }
        return MarketplaceUploadPolicy.isSupportedR2Upload(fileURL: URL(fileURLWithPath: path))
    }

    func addMediaFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .mpeg4Movie,
            .quickTimeMovie,
            .gif
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Wallpaper"

        guard panel.runModal() == .OK else {
            return
        }

        let additions = panel.urls.map { url in
            WallpaperLibraryItem(
                id: UUID().uuidString,
                name: url.deletingPathExtension().lastPathComponent,
                kind: Self.isGIFFile(url) ? .gif : .video,
                videoPath: url.path,
                webURLString: nil,
                motionScene: .aurora,
                motionPalette: .aurora,
                isBuiltIn: false
            )
        }

        schedule { model in
            model.libraryItems.append(contentsOf: additions)
            if let first = additions.first {
                model.selectedItemID = first.id
            }
            model.errorMessage = nil
        }
    }

    func addWebsite() {
        let trimmed = webURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            schedule { $0.errorMessage = "Enter a valid URL." }
            return
        }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard let url = URL(string: normalized), Self.isSupportedWebURL(url) else {
            schedule { $0.errorMessage = "Enter a valid URL." }
            return
        }

        let item = WallpaperLibraryItem(
            id: UUID().uuidString,
            name: url.host ?? normalized,
            kind: .web,
            videoPath: nil,
            webURLString: normalized,
            motionScene: .aurora,
            motionPalette: .aurora,
            isBuiltIn: false
        )
        schedule { model in
            model.libraryItems.append(item)
            model.selectedItemID = item.id
            model.webURLDraft = ""
            model.errorMessage = nil
        }
    }

    func refreshMarketplace() {
        Task { @MainActor in
            await refreshMarketplaceNow()
        }
    }

    func refreshDiscoverWallpapers() {
        Task { @MainActor in
            await refreshDiscoverWallpapersNow()
        }
    }

    func refreshMyUploads() {
        Task { @MainActor in
            await refreshMyUploadsNow()
        }
    }

    func saveProfileDisplayName() {
        Task { @MainActor in
            await saveProfileDisplayNameNow()
        }
    }

    func uploadMarketplaceWallpaperFromFile() {
        guard authenticatedUser != nil else {
            discoverMessage = "Sign in from Profiles before uploading wallpapers."
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Marketplace Upload"
        panel.message = "Choose an MP4 or MOV wallpaper to upload to MotionDock Marketplace."

        guard panel.runModal() == .OK, let fileURL = panel.urls.first else {
            return
        }

        let title = fileURL.deletingPathExtension().lastPathComponent
        Task { @MainActor in
            await uploadR2MarketplaceFileNow(
                fileURL: fileURL,
                title: title,
                description: nil,
                category: MarketplaceCategory.other.rawValue,
                confirmedRights: false,
                source: .discover
            )
        }
    }

    func uploadDiscoverMarketplaceWallpaper(
        fileURL: URL,
        title: String,
        description: String,
        category: MarketplaceCategory,
        confirmedRights: Bool
    ) {
        Task { @MainActor in
            await uploadR2MarketplaceFileNow(
                fileURL: fileURL,
                title: title,
                description: description,
                category: category.rawValue,
                confirmedRights: confirmedRights,
                source: .discover
            )
        }
    }

    func selectDiscoverWallpaper(_ id: String) {
        selectedDiscoverWallpaperID = id
    }

    func clearDiscoverSelection() {
        selectedDiscoverWallpaperID = nil
    }

    func requestAddDiscoverWallpaperToLibrary(_ item: DiscoverWallpaper) {
        Task { @MainActor in
            await addDiscoverWallpaperToLibraryNow(item)
        }
    }

    func toggleDiscoverLike(_ item: DiscoverWallpaper) {
        Task { @MainActor in
            await toggleDiscoverLikeNow(item)
        }
    }

    func discoverLikeIsBusy(_ item: DiscoverWallpaper) -> Bool {
        discoverLikeBusyItemIDs.contains(item.id)
    }

    func discoverReportIsBusy(_ item: DiscoverWallpaper) -> Bool {
        discoverReportBusyItemID == item.id
    }

    func discoverWallpaperIsInLibrary(_ item: DiscoverWallpaper) -> Bool {
        libraryItems.contains { $0.id == discoverLibraryItemID(for: item) }
    }

    func uploadSelectedItemToMarketplace() {
        Task { @MainActor in
            await uploadSelectedItemToMarketplaceNow()
        }
    }

    func reportDiscoverWallpaper(
        _ item: DiscoverWallpaper,
        reason: MarketplaceReportReason,
        details: String
    ) {
        Task { @MainActor in
            await reportDiscoverWallpaperNow(
                item,
                reason: reason,
                details: details
            )
        }
    }

    func downloadMarketplaceItem(_ item: MarketplaceItem, apply: Bool) {
        Task { @MainActor in
            await downloadMarketplaceItemNow(item, apply: apply)
        }
    }

    func myUploadIsBusy(_ item: DiscoverWallpaper) -> Bool {
        myUploadsBusyItemID == item.id
    }

    func updateMyUpload(
        _ item: DiscoverWallpaper,
        title: String,
        description: String,
        category: MarketplaceCategory
    ) {
        Task { @MainActor in
            await updateMyUploadNow(
                item,
                title: title,
                description: description,
                category: category
            )
        }
    }

    func deleteMyUpload(_ item: DiscoverWallpaper) {
        Task { @MainActor in
            await deleteMyUploadNow(item)
        }
    }

    func refreshAuthSession() {
        Task { @MainActor in
            await restoreAuthSessionNow()
        }
    }

    func signInWithGoogle() {
        Task { @MainActor in
            await signInWithGoogleNow(forceAccountSelection: true)
        }
    }

    func useAnotherGoogleAccount() {
        Task { @MainActor in
            await signInWithGoogleNow(forceAccountSelection: true, signOutFirst: true)
        }
    }

    func handleAuthCallbackURL(_ url: URL) {
        guard MotionDockSupabaseAuthService.isOAuthCallbackURL(url) else {
            return
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryDescription = queryItems
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let code = MotionDockSupabaseAuthService.authorizationCode(in: url)

        NSLog("[MotionDock OAuth] received callback URL: %@", url.absoluteString)
        NSLog("[MotionDock OAuth] query items: %@", queryDescription)
        NSLog("[MotionDock OAuth] extracted code: %@", code.map { "present(length=\($0.count))" } ?? "missing")

        if let callbackError = MotionDockSupabaseAuthService.callbackErrorMessage(in: url) {
            let error = MotionDockAuthError.invalidOAuthCallback("Google sign-in failed: \(callbackError)")
            authMessage = error.localizedDescription
            NSLog("[MotionDock OAuth] callback error: %@", error.localizedDescription)
            _ = authService.failPendingOAuthCallback(with: error)
            return
        }

        guard code != nil else {
            let error = MotionDockAuthError.invalidOAuthCallback(
                "MotionDock received an auth callback without a Google authorization code."
            )
            authMessage = error.localizedDescription
            NSLog("[MotionDock OAuth] callback ignored: %@", error.localizedDescription)
            _ = authService.failPendingOAuthCallback(with: error)
            return
        }

        authMessage = "Completing Google sign-in..."
        if authService.completePendingOAuthCallback(url) {
            return
        }

        Task { @MainActor in
            await completeGoogleOAuthCallbackNow(url)
        }
    }

    func signOutAccount() {
        Task { @MainActor in
            await signOutAccountNow()
        }
    }

    func saveSupabaseConfiguration() {
        Task { @MainActor in
            await saveSupabaseConfigurationNow()
        }
    }

    func isFavorite(_ item: WallpaperLibraryItem) -> Bool {
        favoriteItemIDs.contains(item.id)
    }

    func toggleFavorite(_ item: WallpaperLibraryItem) {
        schedule { model in
            if model.favoriteItemIDs.contains(item.id) {
                model.favoriteItemIDs.remove(item.id)
            } else {
                model.favoriteItemIDs.insert(item.id)
            }
        }
    }

    func revealSelectedInFinder() {
        guard let url = selectedLocalFileURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeSelectedItem() {
        schedule { $0.removeSelectedItemNow() }
    }

    func selectItem(_ id: String) {
        schedule { $0.setSelectedItem(id, restart: true) }
    }

    func setPlaylistEnabled(_ enabled: Bool) {
        schedule { model in
            guard model.playlistEnabled != enabled else {
                return
            }
            model.playlistEnabled = enabled
        }
    }

    func setPlaylistIntervalMinutes(_ minutes: Double) {
        schedule { model in
            guard model.playlistIntervalMinutes != minutes else {
                return
            }
            model.playlistIntervalMinutes = minutes
        }
    }

    func setDisplayMode(_ mode: DisplayMode) {
        schedule { model in
            guard model.displayMode != mode else {
                return
            }
            model.displayMode = mode
        }
    }

    func setPerformanceProfile(_ profile: PerformanceProfile) {
        schedule { model in
            guard model.performanceProfile != profile else {
                return
            }
            model.performanceProfile = profile
        }
    }

    func setPerformancePolicy(_ policy: PerformancePolicy) {
        schedule { model in
            guard model.performancePolicy != policy else {
                return
            }
            model.performancePolicy = policy
        }
    }

    func setMuted(_ muted: Bool) {
        schedule { model in
            guard model.isMuted != muted else {
                return
            }
            model.isMuted = muted
        }
    }

    func setFillMode(_ mode: VideoFillMode) {
        schedule { model in
            guard model.fillMode != mode else {
                return
            }
            model.fillMode = mode
        }
    }

    func setStartAtLoginEnabled(_ enabled: Bool) {
        schedule { $0.setStartAtLoginEnabledNow(enabled) }
    }

    func setShowInDock(_ enabled: Bool) {
        schedule { model in
            guard model.showInDock != enabled else {
                return
            }

            model.showInDock = enabled
            UserDefaults.standard.set(enabled, forKey: DefaultsKey.showInDock)
            MotionDockDockVisibility.apply(showInDock: enabled, activateMainWindow: enabled)
        }
    }

    func requestSettings() {
        settingsRequestCounter += 1
    }

    private func removeSelectedItemNow() {
        guard removableSelection, let selectedItem else {
            return
        }

        libraryItems.removeAll { $0.id == selectedItem.id }
        setSelectedItem(libraryItems.first?.id ?? WallpaperLibraryItem.defaults[0].id, restart: false)
        restartNowIfRunning()
    }

    func start() {
        schedule { $0.startNow() }
    }

    private func startNow() {
        guard let configuration = makeConfiguration(setError: true) else {
            return
        }

        do {
            try manager.start(with: configuration)
            isRunning = true
            isSuspended = false
            errorMessage = nil
            saveLastWallpaperRecord(for: configuration.item)
            configurePlaylistTimer()
            configurePerformanceTimer()
        } catch {
            isRunning = false
            isSuspended = false
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        schedule { $0.stopNow() }
    }

    func stopForQuit() {
        stopNow()
    }

    private func stopNow() {
        manager.stop()
        isRunning = false
        isSuspended = false
        playlistTimer?.invalidate()
        playlistTimer = nil
        performanceTimer?.invalidate()
        performanceTimer = nil
    }

    func restoreLastWallpaper() {
        schedule { $0.restoreLastWallpaperNow(reportMissingRecord: true) }
    }

    func restoreLastWallpaperOnLaunch() {
        schedule { $0.restoreLastWallpaperNow(reportMissingRecord: false) }
    }

    private func scheduleRestartIfRunning() {
        guard isRunning else {
            return
        }
        schedule { $0.restartNowIfRunning() }
    }

    private func restartNowIfRunning() {
        guard isRunning else {
            return
        }
        startNow()
    }

    func advancePlaylist() {
        schedule { $0.advancePlaylistNow() }
    }

    private func advancePlaylistNow() {
        guard libraryItems.count > 1, let currentIndex = libraryItems.firstIndex(where: { $0.id == selectedItemID }) else {
            return
        }

        for offset in 1...libraryItems.count {
            let nextIndex = (currentIndex + offset) % libraryItems.count
            setSelectedItem(libraryItems[nextIndex].id, restart: false)
            if canStart {
                restartNowIfRunning()
                return
            }
        }
    }

    private func makeConfiguration(setError: Bool) -> WallpaperConfiguration? {
        guard let selectedItem else {
            if setError {
                errorMessage = "No wallpaper is selected."
            }
            return nil
        }

        switch selectedItem.kind {
        case .motion:
            return WallpaperConfiguration(
                item: selectedItem,
                source: .motion(scene: selectedItem.motionScene, palette: selectedItem.motionPalette),
                muted: isMuted,
                fillMode: fillMode,
                displayMode: displayMode,
                performanceProfile: performanceProfile
            )
        case .video:
            guard let videoPath = selectedItem.videoPath, !videoPath.isEmpty else {
                if setError {
                    errorMessage = "The video path is empty."
                }
                return nil
            }

            let url = URL(fileURLWithPath: videoPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                if setError {
                    errorMessage = "The selected video file could not be found."
                }
                return nil
            }

            return WallpaperConfiguration(
                item: selectedItem,
                source: .video(url),
                muted: isMuted,
                fillMode: fillMode,
                displayMode: displayMode,
                performanceProfile: performanceProfile
            )
        case .gif:
            guard let gifPath = selectedItem.videoPath, !gifPath.isEmpty else {
                if setError {
                    errorMessage = "The GIF path is empty."
                }
                return nil
            }

            let url = URL(fileURLWithPath: gifPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                if setError {
                    errorMessage = "The selected GIF file could not be found."
                }
                return nil
            }

            return WallpaperConfiguration(
                item: selectedItem,
                source: .gif(url),
                muted: isMuted,
                fillMode: fillMode,
                displayMode: displayMode,
                performanceProfile: performanceProfile
            )
        case .web:
            guard let urlString = selectedItem.webURLString, let url = URL(string: urlString) else {
                if setError {
                    errorMessage = "The web URL could not be loaded."
                }
                return nil
            }

            return WallpaperConfiguration(
                item: selectedItem,
                source: .web(url),
                muted: isMuted,
                fillMode: fillMode,
                displayMode: displayMode,
                performanceProfile: performanceProfile
            )
        }
    }

    private func refreshMarketplaceNow() async {
        marketplaceIsLoading = true
        marketplaceMessage = nil
        defer { marketplaceIsLoading = false }

        do {
            if authService.isConfigured {
                marketplaceItems = try await authService.listMarketplaceWallpapers()
            } else {
                guard let baseURL = marketplaceBaseURL else {
                    marketplaceMessage = MarketplaceError.invalidServerURL.localizedDescription
                    return
                }
                let listURL = baseURL.appendingPathComponent("api/wallpapers")
                let (data, response) = try await URLSession.shared.data(from: listURL)
                try validate(response: response, data: data)
                marketplaceItems = try JSONDecoder().decode([MarketplaceItem].self, from: data)
            }
            marketplaceMessage = marketplaceItems.isEmpty ? "No marketplace wallpapers yet." : nil
        } catch {
            marketplaceMessage = error.localizedDescription
        }
    }

    private func refreshDiscoverWallpapersNow() async {
        discoverIsLoading = true
        discoverMessage = nil
        defer { discoverIsLoading = false }

        guard authService.isConfigured else {
            discoverWallpapers = []
            selectedDiscoverWallpaperID = nil
            discoverMessage = "Configure Supabase in Settings to load Discover."
            return
        }

        do {
            let wallpapers = try await authService.listDiscoverWallpapers()
            let likedIDs: Set<String>
            let likedStateWarning: String?

            if let authenticatedUser {
                do {
                    likedIDs = try await authService.listLikedDiscoverWallpaperIDs(userID: authenticatedUser.id)
                    likedStateWarning = nil
                } catch {
                    likedIDs = []
                    likedStateWarning = "Could not load liked wallpapers: \(error.localizedDescription)"
                }
            } else {
                likedIDs = []
                likedStateWarning = nil
            }

            let mergedWallpapers = wallpapers.map { $0.withLikeState(
                isLiked: likedIDs.contains($0.id),
                likesCount: $0.likesCount
            ) }
            discoverWallpapers = mergedWallpapers

            if let selectedDiscoverWallpaperID,
               mergedWallpapers.contains(where: { $0.id == selectedDiscoverWallpaperID }) {
                // Keep the current Discover selection when the item still exists.
            } else {
                selectedDiscoverWallpaperID = mergedWallpapers.first?.id
            }

            discoverMessage = mergedWallpapers.isEmpty ? "No marketplace wallpapers yet." : likedStateWarning
        } catch {
            discoverWallpapers = []
            selectedDiscoverWallpaperID = nil
            discoverMessage = error.localizedDescription
        }
    }

    private func refreshMyUploadsNow() async {
        guard let user = authenticatedUser else {
            myUploads = []
            myUploadsMessage = "Sign in to manage your uploads."
            return
        }

        guard authService.isConfigured else {
            myUploads = []
            myUploadsMessage = "Configure Supabase in Settings to manage uploads."
            return
        }

        myUploadsIsLoading = true
        myUploadsMessage = nil
        defer { myUploadsIsLoading = false }

        do {
            myUploads = try await authService.listMyUploads(userID: user.id)
            myUploadsMessage = myUploads.isEmpty ? "No uploads yet." : nil
        } catch {
            myUploads = []
            myUploadsMessage = error.localizedDescription
        }
    }

    private func updateMyUploadNow(
        _ item: DiscoverWallpaper,
        title: String,
        description: String,
        category: MarketplaceCategory
    ) async {
        guard authenticatedUser?.id == item.uploaderID else {
            myUploadsMessage = "You can only edit wallpapers uploaded by your account."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            myUploadsMessage = "Title is required."
            return
        }

        myUploadsBusyItemID = item.id
        myUploadsMessage = "Saving changes..."
        defer { myUploadsBusyItemID = nil }

        do {
            _ = try await authService.updateMyUploadMetadata(
                wallpaperID: item.id,
                title: trimmedTitle,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.rawValue
            )
            await refreshMyUploadsNow()
            await refreshDiscoverWallpapersNow()
            selectedDiscoverWallpaperID = item.id
            myUploadsMessage = "Upload updated."
        } catch {
            myUploadsMessage = "Could not update upload: \(error.localizedDescription)"
        }
    }

    private func deleteMyUploadNow(_ item: DiscoverWallpaper) async {
        guard authenticatedUser?.id == item.uploaderID else {
            myUploadsMessage = "You can only delete wallpapers uploaded by your account."
            return
        }

        myUploadsBusyItemID = item.id
        myUploadsMessage = "Deleting upload..."
        defer { myUploadsBusyItemID = nil }

        do {
            let storageService = try CloudflareR2StorageService()
            try await storageService.deleteAssets(for: item)
            try await authService.deleteMyUpload(wallpaperID: item.id)

            myUploads.removeAll { $0.id == item.id }
            discoverWallpapers.removeAll { $0.id == item.id }
            if selectedDiscoverWallpaperID == item.id {
                selectedDiscoverWallpaperID = discoverWallpapers.first?.id
            }

            await refreshMyUploadsNow()
            await refreshDiscoverWallpapersNow()
            myUploadsMessage = "Upload deleted."
        } catch {
            myUploadsMessage = "Could not delete upload: \(error.localizedDescription)"
        }
    }

    private func uploadR2MarketplaceFileNow(
        fileURL: URL,
        title: String,
        description: String?,
        category: String,
        confirmedRights: Bool,
        source: MarketplaceUploadSource
    ) async {
        guard let uploader = authenticatedUser else {
            setMarketplaceUploadMessage("Sign in from Profiles before uploading wallpapers.", source: source)
            return
        }

        guard authService.isConfigured else {
            setMarketplaceUploadMessage("Configure Supabase in Settings before uploading wallpapers.", source: source)
            return
        }

        guard confirmedRights else {
            setMarketplaceUploadMessage("You must accept the MotionDock Marketplace Upload Terms before uploading.", source: source)
            return
        }

        guard MarketplaceUploadPolicy.isSupportedR2Upload(fileURL: fileURL) else {
            setMarketplaceUploadMessage(
                "Marketplace R2 uploads support \(MarketplaceUploadPolicy.supportedR2UploadTypesText).",
                source: source
            )
            return
        }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else {
            setMarketplaceUploadMessage(MarketplaceError.missingLocalFile.localizedDescription, source: source)
            return
        }
        guard fileSize <= MarketplaceUploadPolicy.maxUploadBytes else {
            setMarketplaceUploadMessage(
                MarketplaceError.uploadTooLarge(limitBytes: MarketplaceUploadPolicy.maxUploadBytes).localizedDescription,
                source: source
            )
            return
        }

        setMarketplaceUploadLoading(true, source: source)
        setMarketplaceUploadMessage("Uploading to Cloudflare R2...", source: source)
        defer { setMarketplaceUploadLoading(false, source: source) }

        do {
            let objectID = UUID().uuidString.lowercased()
            let storageService = try CloudflareR2StorageService()
            let thumbnailAsset: MarketplaceStoredAsset?
            let thumbnailWarning: String?

            setMarketplaceUploadMessage("Generating thumbnail...", source: source)
            do {
                let thumbnailURL = try await generateMarketplaceThumbnail(
                    for: fileURL,
                    objectID: objectID
                )
                setMarketplaceUploadMessage("Uploading thumbnail...", source: source)
                thumbnailAsset = try await storageService.uploadThumbnail(
                    fileURL: thumbnailURL,
                    objectID: objectID
                )
                thumbnailWarning = nil
            } catch {
                thumbnailAsset = nil
                thumbnailWarning = "Marketplace upload complete. Thumbnail unavailable; using placeholder."
            }

            setMarketplaceUploadMessage("Uploading to Cloudflare R2...", source: source)
            let uploadedAsset = try await storageService.uploadWallpaper(
                fileURL: fileURL,
                objectID: objectID
            )
            let insertedWallpaper = try await authService.insertR2MarketplaceWallpaper(
                id: objectID,
                title: normalizedMarketplaceTitle(title, fileURL: fileURL),
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? MarketplaceCategory.other.rawValue
                    : category.trimmingCharacters(in: .whitespacesAndNewlines),
                uploadedAsset: uploadedAsset,
                thumbnailAsset: thumbnailAsset,
                uploader: uploader,
                confirmedRights: confirmedRights
            )

            await refreshDiscoverWallpapersNow()
            await refreshMyUploadsNow()
            selectedDiscoverWallpaperID = insertedWallpaper.id
            setMarketplaceUploadMessage(
                thumbnailWarning ?? "Marketplace upload complete. Discover refreshed.",
                source: source
            )
        } catch {
            setMarketplaceUploadMessage(error.localizedDescription, source: source)
        }
    }

    private func setMarketplaceUploadLoading(_ isLoading: Bool, source: MarketplaceUploadSource) {
        switch source {
        case .discover:
            discoverUploadIsLoading = isLoading
        case .settings:
            marketplaceIsLoading = isLoading
        }
    }

    private func setMarketplaceUploadMessage(_ message: String, source: MarketplaceUploadSource) {
        switch source {
        case .discover:
            discoverMessage = message
        case .settings:
            marketplaceMessage = message
        }
    }

    private func normalizedMarketplaceTitle(_ title: String, fileURL: URL) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTitle.isEmpty ? "Untitled Wallpaper" : fallbackTitle
    }

    private func generateMarketplaceThumbnail(for fileURL: URL, objectID: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)

            let image: CGImage
            do {
                image = try generator.copyCGImage(
                    at: CMTime(seconds: 1, preferredTimescale: 600),
                    actualTime: nil
                )
            } catch {
                image = try generator.copyCGImage(at: .zero, actualTime: nil)
            }

            let representation = NSBitmapImageRep(cgImage: image)
            guard let data = representation.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.82]
            ) else {
                throw MarketplaceThumbnailError.imageEncodingFailed
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MotionDock-Thumbnails", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let url = directory.appendingPathComponent("\(objectID).jpg")
            try data.write(to: url, options: .atomic)
            return url
        }.value
    }

    private func uploadSelectedItemToMarketplaceNow() async {
        guard authenticatedUser != nil else {
            marketplaceMessage = "Sign in from Profiles before uploading."
            return
        }
        guard let selectedItem, selectedItem.kind == .video else {
            marketplaceMessage = "Marketplace R2 uploads support \(MarketplaceUploadPolicy.supportedR2UploadTypesText)."
            return
        }
        guard let path = selectedItem.videoPath, FileManager.default.fileExists(atPath: path) else {
            marketplaceMessage = MarketplaceError.missingLocalFile.localizedDescription
            return
        }

        let fileURL = URL(fileURLWithPath: path)
        guard MarketplaceUploadPolicy.isSupportedR2Upload(fileURL: fileURL) else {
            marketplaceMessage = "Marketplace R2 uploads support \(MarketplaceUploadPolicy.supportedR2UploadTypesText)."
            return
        }

        await uploadR2MarketplaceFileNow(
            fileURL: fileURL,
            title: selectedItem.name,
            description: nil,
            category: MarketplaceCategory.other.rawValue,
            confirmedRights: false,
            source: .settings
        )
    }

    private func downloadMarketplaceItemNow(_ item: MarketplaceItem, apply: Bool) async {
        guard let kind = item.supportedKind else {
            marketplaceMessage = MarketplaceError.unsupportedDownload.localizedDescription
            return
        }

        marketplaceBusyItemID = item.id
        marketplaceMessage = apply ? "Downloading and applying..." : "Downloading..."
        defer { marketplaceBusyItemID = nil }

        do {
            let data: Data
            if item.storagePath != nil, authService.isConfigured {
                data = try await authService.downloadMarketplaceWallpaper(item)
            } else {
                guard let baseURL = marketplaceBaseURL else {
                    marketplaceMessage = MarketplaceError.invalidServerURL.localizedDescription
                    return
                }
                guard let downloadURL = URL(string: item.downloadURL, relativeTo: baseURL)?.absoluteURL else {
                    marketplaceMessage = MarketplaceError.invalidResponse.localizedDescription
                    return
                }
                let (downloadedData, response) = try await URLSession.shared.data(from: downloadURL)
                try validate(response: response, data: downloadedData)
                data = downloadedData
            }

            let savedURL = try saveDownloadedMarketplaceFile(data: data, item: item)
            let libraryItem = WallpaperLibraryItem(
                id: "marketplace-\(item.id)",
                name: item.title,
                kind: kind,
                videoPath: savedURL.path,
                webURLString: nil,
                motionScene: .aurora,
                motionPalette: .aurora,
                isBuiltIn: false,
                uploaderID: item.uploaderID
            )

            if let existingIndex = libraryItems.firstIndex(where: { $0.id == libraryItem.id }) {
                libraryItems[existingIndex] = libraryItem
            } else {
                libraryItems.append(libraryItem)
            }

            setSelectedItem(libraryItem.id, restart: false)
            marketplaceMessage = apply ? "Downloaded and applied." : "Added to Library."

            if apply {
                startNow()
            }
        } catch {
            marketplaceMessage = error.localizedDescription
        }
    }

    private func addDiscoverWallpaperToLibraryNow(_ item: DiscoverWallpaper) async {
        let libraryItemID = discoverLibraryItemID(for: item)
        if libraryItems.contains(where: { $0.id == libraryItemID }) {
            setSelectedItem(libraryItemID, restart: false)
            discoverMessage = "Already in Library."
            return
        }

        guard let videoURL = item.videoURLValue else {
            discoverMessage = "This marketplace wallpaper does not include a downloadable video URL."
            return
        }

        guard let scheme = videoURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            discoverMessage = "Discover downloads require an http or https video URL."
            return
        }

        discoverBusyItemID = item.id
        discoverMessage = "Adding to Library..."
        defer { discoverBusyItemID = nil }

        do {
            let (downloadedData, response) = try await URLSession.shared.data(from: videoURL)
            try validate(response: response, data: downloadedData)

            let kind = try discoverWallpaperKind(for: videoURL, response: response)
            let savedURL = try saveDownloadedDiscoverWallpaperFile(
                data: downloadedData,
                item: item,
                sourceURL: videoURL,
                response: response,
                kind: kind
            )
            let libraryItem = WallpaperLibraryItem(
                id: libraryItemID,
                name: item.displayTitle,
                kind: kind,
                videoPath: savedURL.path,
                webURLString: nil,
                motionScene: .aurora,
                motionPalette: .aurora,
                isBuiltIn: false,
                uploaderID: item.uploaderID
            )

            libraryItems.append(libraryItem)
            setSelectedItem(libraryItem.id, restart: false)

            do {
                let updatedDownloads = try await authService.incrementDiscoverDownloads(for: item)
                updateDiscoverDownloads(for: item.id, downloads: updatedDownloads)
                discoverMessage = "Added to Library."
            } catch {
                discoverMessage = "Added to Library, but downloads count could not be updated: \(error.localizedDescription)"
            }
        } catch {
            discoverMessage = error.localizedDescription
        }
    }

    private func toggleDiscoverLikeNow(_ item: DiscoverWallpaper) async {
        guard authenticatedUser != nil else {
            discoverMessage = "Sign in to like marketplace wallpapers."
            return
        }

        guard !discoverLikeBusyItemIDs.contains(item.id) else {
            return
        }

        let currentItem = discoverWallpapers.first { $0.id == item.id } ?? item
        let previousIsLiked = currentItem.isLiked
        let previousLikesCount = currentItem.likesCount
        let nextIsLiked = !previousIsLiked
        let nextLikesCount = max(0, previousLikesCount + (nextIsLiked ? 1 : -1))

        discoverLikeBusyItemIDs.insert(item.id)
        updateDiscoverLikeState(
            for: item.id,
            isLiked: nextIsLiked,
            likesCount: nextLikesCount
        )
        discoverMessage = nextIsLiked ? "Liked." : "Like removed."
        defer { discoverLikeBusyItemIDs.remove(item.id) }

        do {
            let result = try await authService.toggleDiscoverLike(
                wallpaperID: item.id
            )
            updateDiscoverLikeState(
                for: item.id,
                isLiked: result.liked,
                likesCount: result.likesCount
            )
            discoverMessage = result.liked ? "Liked." : "Like removed."
        } catch {
            updateDiscoverLikeState(
                for: item.id,
                isLiked: previousIsLiked,
                likesCount: previousLikesCount
            )
            discoverMessage = "Could not update like: \(error.localizedDescription)"
        }
    }

    private func reportDiscoverWallpaperNow(
        _ item: DiscoverWallpaper,
        reason: MarketplaceReportReason,
        details: String
    ) async {
        guard authenticatedUser != nil else {
            discoverMessage = "Sign in to report marketplace wallpapers."
            return
        }

        guard discoverReportBusyItemID != item.id else {
            return
        }

        discoverReportBusyItemID = item.id
        discoverMessage = "Submitting report..."
        defer { discoverReportBusyItemID = nil }

        do {
            let result = try await authService.reportWallpaper(
                wallpaperID: item.id,
                reason: reason,
                details: details.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            updateDiscoverReportState(
                for: item.id,
                reportCount: result.reportCount,
                isHidden: result.isHidden
            )

            if result.isHidden {
                discoverWallpapers.removeAll { $0.id == item.id }
                if selectedDiscoverWallpaperID == item.id {
                    selectedDiscoverWallpaperID = nil
                }
                discoverMessage = "Report submitted. This wallpaper is now hidden."
            } else {
                discoverMessage = "Report submitted."
            }

            await refreshDiscoverWallpapersNow()
            if result.isHidden {
                selectedDiscoverWallpaperID = nil
            }
        } catch {
            let message = error.localizedDescription
            discoverMessage = message.localizedCaseInsensitiveContains("already reported")
                ? "You already reported this wallpaper."
                : "Could not submit report via \(MotionDockSupabaseAuthService.reportWallpaperRPCDescription): \(message)"
        }
    }

    private var marketplaceBaseURL: URL? {
        let trimmed = marketplaceServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil, components.host != nil else {
            return nil
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url
    }

    private func saveProfileDisplayNameNow() async {
        guard let user = authenticatedUser else {
            authMessage = "Sign in before changing your display name."
            return
        }

        let displayName = profileDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            authMessage = "Enter a display name."
            return
        }

        profileDisplayNameIsSaving = true
        authMessage = "Saving display name..."
        defer { profileDisplayNameIsSaving = false }

        do {
            let updatedUser = try await authService.updateProfileDisplayName(
                user: user,
                displayName: displayName
            )
            authenticatedUser = updatedUser
            syncProfileDisplayNameDraft()
            authMessage = "Display name updated."
            await refreshMyUploadsNow()
            await refreshDiscoverWallpapersNow()
        } catch {
            authMessage = "Could not update display name: \(error.localizedDescription)"
        }
    }

    private func saveSupabaseConfigurationNow() async {
        let rawURL = supabaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let anonKey = supabaseAnonKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let marketplaceBucket = supabaseMarketplaceBucketDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let marketplaceTable = supabaseMarketplaceTableDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let url = URL(string: rawURL),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host != nil
        else {
            supabaseConfigurationMessage = "Enter a valid Supabase project URL."
            return
        }

        guard !anonKey.isEmpty else {
            supabaseConfigurationMessage = "Enter your Supabase anon key."
            return
        }

        do {
            try MotionDockSupabaseConfiguration.save(
                url: url,
                anonKey: anonKey,
                marketplaceBucket: marketplaceBucket.isEmpty ? MotionDockSupabaseConfiguration.defaultMarketplaceBucket : marketplaceBucket,
                marketplaceTable: marketplaceTable.isEmpty ? MotionDockSupabaseConfiguration.defaultMarketplaceTable : marketplaceTable
            )
            authService = MotionDockSupabaseAuthService()
            authenticatedUser = nil
            syncProfileDisplayNameDraft()
            myUploads = []
            myUploadsMessage = nil
            clearDiscoverLikeState()
            authMessage = nil
            supabaseConfigurationMessage = "Supabase configuration saved. You can now sign in with Google."
            await restoreAuthSessionNow()
        } catch {
            supabaseConfigurationMessage = error.localizedDescription
        }
    }

    private func restoreAuthSessionNow() async {
        guard authService.isConfigured else {
            authMessage = nil
            authenticatedUser = nil
            syncProfileDisplayNameDraft()
            myUploads = []
            myUploadsMessage = nil
            return
        }

        authIsLoading = true
        defer { authIsLoading = false }

        do {
            authenticatedUser = try await authService.restoreSession()
            syncProfileDisplayNameDraft()
            authMessage = authenticatedUser == nil ? nil : "Signed in as \(profileDisplayText)."
            if authenticatedUser != nil {
                await refreshMyUploadsNow()
                if !discoverWallpapers.isEmpty {
                    await refreshDiscoverWallpapersNow()
                }
            }
        } catch {
            authenticatedUser = nil
            syncProfileDisplayNameDraft()
            myUploads = []
            myUploadsMessage = nil
            clearDiscoverLikeState()
            authMessage = error.localizedDescription
        }
    }

    private func signInWithGoogleNow(forceAccountSelection: Bool, signOutFirst: Bool = false) async {
        authIsLoading = true
        authMessage = signOutFirst ? "Signing out and opening Google account chooser..." : "Opening Google sign-in..."
        defer { authIsLoading = false }

        do {
            if signOutFirst {
                try await authService.signOut()
                authenticatedUser = nil
                syncProfileDisplayNameDraft()
                myUploads = []
                myUploadsMessage = nil
                clearDiscoverLikeState()
            }

            authenticatedUser = try await authService.signInWithGoogle(forceAccountSelection: forceAccountSelection)
            syncProfileDisplayNameDraft()
            authMessage = "Signed in as \(profileDisplayText)."
            await refreshMyUploadsNow()
            if !discoverWallpapers.isEmpty {
                await refreshDiscoverWallpapersNow()
            }
        } catch {
            NSLog("[MotionDock OAuth] Google sign-in failed: %@", error.localizedDescription)
            authMessage = googleAuthErrorMessage(for: error)
        }
    }

    private func completeGoogleOAuthCallbackNow(_ url: URL) async {
        authIsLoading = true
        authMessage = "Completing Google sign-in..."
        defer { authIsLoading = false }

        do {
            authenticatedUser = try await authService.completeOAuthCallback(url)
            syncProfileDisplayNameDraft()
            authMessage = "Signed in as \(profileDisplayText)."
            await refreshMyUploadsNow()
            if !discoverWallpapers.isEmpty {
                await refreshDiscoverWallpapersNow()
            }
        } catch {
            authenticatedUser = nil
            syncProfileDisplayNameDraft()
            myUploads = []
            myUploadsMessage = nil
            clearDiscoverLikeState()
            NSLog("[MotionDock OAuth] callback completion failed: %@", error.localizedDescription)
            authMessage = googleAuthErrorMessage(for: error)
        }
    }

    private func signOutAccountNow() async {
        authIsLoading = true
        defer { authIsLoading = false }

        do {
            try await authService.signOut()
            authenticatedUser = nil
            syncProfileDisplayNameDraft()
            myUploads = []
            myUploadsMessage = nil
            clearDiscoverLikeState()
            authMessage = "Signed out."
        } catch {
            authMessage = error.localizedDescription
        }
    }

    private func googleAuthErrorMessage(for error: Error) -> String {
        error.localizedDescription
    }

    private func syncProfileDisplayNameDraft() {
        profileDisplayNameDraft = authenticatedUser?.displayName ?? ""
    }

    private var selectedLocalFileURL: URL? {
        guard let path = selectedItem?.videoPath, !path.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func setStartAtLoginEnabledNow(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                startAtLoginEnabled = true
                UserDefaults.standard.set(true, forKey: DefaultsKey.startAtLoginEnabled)
                loginItemMessage = "MotionDock will start when you log in."
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                startAtLoginEnabled = false
                UserDefaults.standard.set(false, forKey: DefaultsKey.startAtLoginEnabled)
                loginItemMessage = "MotionDock will not start at login."
            }
        } catch {
            startAtLoginEnabled = !enabled
            UserDefaults.standard.set(startAtLoginEnabled, forKey: DefaultsKey.startAtLoginEnabled)
            loginItemMessage = "Login item update failed: \(error.localizedDescription)"
        }
    }

    private func saveLastWallpaperRecord(for item: WallpaperLibraryItem) {
        let record = LastWallpaperRecord(item: item)
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        UserDefaults.standard.set(data, forKey: DefaultsKey.lastWallpaperRecord)
    }

    @discardableResult
    private func restoreLastWallpaperNow(reportMissingRecord: Bool) -> Bool {
        guard
            let data = UserDefaults.standard.data(forKey: DefaultsKey.lastWallpaperRecord),
            let record = try? JSONDecoder().decode(LastWallpaperRecord.self, from: data)
        else {
            if reportMissingRecord {
                errorMessage = "No previous wallpaper has been saved yet."
            }
            return false
        }

        guard let item = resolveLastWallpaperRecord(record) else {
            return false
        }

        if !libraryItems.contains(where: { $0.id == item.id }) {
            libraryItems.append(item)
        }

        setSelectedItem(item.id, restart: false)
        startNow()
        return isRunning
    }

    private func resolveLastWallpaperRecord(_ record: LastWallpaperRecord) -> WallpaperLibraryItem? {
        let item = libraryItems.first { $0.id == record.id } ?? record.libraryItem

        guard let item else {
            errorMessage = "The last wallpaper could not be restored."
            return nil
        }

        switch item.kind {
        case .motion:
            return item
        case .video, .gif:
            guard let path = item.videoPath, FileManager.default.fileExists(atPath: path) else {
                errorMessage = "The last wallpaper file could not be found: \(item.videoPath ?? "missing path")"
                return nil
            }
            return item
        case .web:
            guard let urlString = item.webURLString, let url = URL(string: urlString), Self.isSupportedWebURL(url) else {
                errorMessage = "The last wallpaper URL is no longer valid."
                return nil
            }
            return item
        }
    }

    private func saveDownloadedMarketplaceFile(data: Data, item: MarketplaceItem) throws -> URL {
        let directory = try marketplaceDownloadsDirectory()
        let filename = safeFilename("\(item.id)-\(item.filename)")
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func saveDownloadedDiscoverWallpaperFile(
        data: Data,
        item: DiscoverWallpaper,
        sourceURL: URL,
        response: URLResponse,
        kind: WallpaperItemKind
    ) throws -> URL {
        let directory = try marketplaceDownloadsDirectory()
        let sourceFilename = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFilename = safeFilename(item.displayTitle)
        let baseFilename = sourceFilename.isEmpty ? fallbackFilename : sourceFilename
        let fileExtension = discoverFileExtension(for: sourceURL, response: response, kind: kind)
        let filenameWithExtension: String

        if URL(fileURLWithPath: baseFilename).pathExtension.isEmpty {
            filenameWithExtension = "\(baseFilename).\(fileExtension)"
        } else {
            filenameWithExtension = baseFilename
        }

        let filename = safeFilename("\(item.id)-\(filenameWithExtension)")
        let url = directory.appendingPathComponent(filename.isEmpty ? "\(item.id).\(fileExtension)" : filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func discoverWallpaperKind(for sourceURL: URL, response: URLResponse) throws -> WallpaperItemKind {
        let pathExtension = sourceURL.pathExtension.lowercased()
        switch pathExtension {
        case "gif":
            return .gif
        case "mp4", "mov", "m4v":
            return .video
        default:
            break
        }

        let mimeType = response.mimeType?.lowercased() ?? ""
        if mimeType == "image/gif" {
            return .gif
        }
        if mimeType.hasPrefix("video/") || mimeType == "application/octet-stream" {
            return .video
        }

        throw MarketplaceError.unsupportedDownload
    }

    private func discoverFileExtension(
        for sourceURL: URL,
        response: URLResponse,
        kind: WallpaperItemKind
    ) -> String {
        let pathExtension = sourceURL.pathExtension.lowercased()
        if MarketplaceUploadPolicy.supportedVideoExtensions.contains(pathExtension)
            || MarketplaceUploadPolicy.supportedGIFExtensions.contains(pathExtension) {
            return pathExtension
        }

        switch response.mimeType?.lowercased() {
        case "image/gif":
            return "gif"
        case "video/quicktime":
            return "mov"
        case "video/x-m4v":
            return "m4v"
        default:
            return kind == .gif ? "gif" : "mp4"
        }
    }

    private func updateDiscoverDownloads(for id: String, downloads: Int) {
        guard let index = discoverWallpapers.firstIndex(where: { $0.id == id }) else {
            return
        }
        discoverWallpapers[index] = discoverWallpapers[index].withDownloads(downloads)
    }

    private func updateDiscoverLikeState(for id: String, isLiked: Bool, likesCount: Int) {
        guard let index = discoverWallpapers.firstIndex(where: { $0.id == id }) else {
            return
        }
        discoverWallpapers[index] = discoverWallpapers[index].withLikeState(
            isLiked: isLiked,
            likesCount: likesCount
        )
    }

    private func updateDiscoverReportState(for id: String, reportCount: Int, isHidden: Bool) {
        guard let index = discoverWallpapers.firstIndex(where: { $0.id == id }) else {
            return
        }
        discoverWallpapers[index] = discoverWallpapers[index].withReportState(
            reportCount: reportCount,
            isHidden: isHidden
        )
    }

    private func clearDiscoverLikeState() {
        discoverLikeBusyItemIDs.removeAll()
        discoverReportBusyItemID = nil
        discoverWallpapers = discoverWallpapers.map { item in
            item.withLikeState(isLiked: false, likesCount: item.likesCount)
        }
    }

    private func discoverLibraryItemID(for item: DiscoverWallpaper) -> String {
        "discover-\(item.id)"
    }

    private func marketplaceDownloadsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("MotionDock", isDirectory: true)
            .appendingPathComponent("Marketplace Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func safeFilename(_ filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return filename.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        fileURL: URL
    ) throws -> Data {
        var body = Data()

        for (name, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }

        let filename = fileURL.lastPathComponent
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType(for: fileURL))\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        return body
    }

    private func mimeType(for url: URL) -> String {
        if Self.isGIFFile(url) {
            return "image/gif"
        }

        switch url.pathExtension.lowercased() {
        case "mov":
            return "video/quicktime"
        case "m4v":
            return "video/x-m4v"
        default:
            return "video/mp4"
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketplaceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let serverError = try? JSONDecoder().decode(MarketplaceServerError.self, from: data) {
                throw MarketplaceError.server(serverError.error)
            }
            throw MarketplaceError.server("Marketplace server error: HTTP \(httpResponse.statusCode)")
        }
    }

    private func isUsable(item: WallpaperLibraryItem) -> Bool {
        switch item.kind {
        case .motion:
            return true
        case .video, .gif:
            guard let videoPath = item.videoPath, !videoPath.isEmpty else {
                return false
            }
            return FileManager.default.fileExists(atPath: videoPath)
        case .web:
            guard let urlString = item.webURLString, let url = URL(string: urlString) else {
                return false
            }
            return Self.isSupportedWebURL(url)
        }
    }

    private func setSelectedItem(_ id: String, restart: Bool) {
        suppressAutomaticRestart = !restart
        selectedItemID = id
        suppressAutomaticRestart = false
    }

    private func updateSelectedItem(_ update: (inout WallpaperLibraryItem) -> Void) {
        guard let index = libraryItems.firstIndex(where: { $0.id == selectedItemID }) else {
            return
        }
        update(&libraryItems[index])
    }

    private func configurePlaylistTimer() {
        playlistTimer?.invalidate()
        playlistTimer = nil

        guard isRunning, playlistEnabled, libraryItems.count > 1 else {
            return
        }

        playlistTimer = Timer.scheduledTimer(withTimeInterval: max(1, playlistIntervalMinutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isSuspended == false else {
                    return
                }
                self?.advancePlaylist()
            }
        }
    }

    private func configurePerformanceTimer() {
        performanceTimer?.invalidate()
        performanceTimer = nil

        guard isRunning, performancePolicy != .keepRunning else {
            manager.resume()
            isSuspended = false
            return
        }

        performanceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePerformancePolicy()
            }
        }
        evaluatePerformancePolicy()
    }

    private func evaluatePerformancePolicy() {
        guard isRunning else {
            return
        }

        if performancePolicy == .keepRunning {
            manager.resume()
            isSuspended = false
            return
        }

        let shouldSuspend = isLowPowerAndBatterySaver || Self.frontmostApplicationCoversDisplay()

        if shouldSuspend {
            manager.suspend(releaseResources: performancePolicy == .stopWhenCovered)
        } else {
            manager.resume()
        }
        isSuspended = shouldSuspend
    }

    private func installSystemTransitionObservers() {
        let defaultCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        addSystemTransitionObserver(center: defaultCenter, name: NSApplication.didChangeScreenParametersNotification)

        [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ].forEach { name in
            addSystemTransitionObserver(center: workspaceCenter, name: name)
        }
    }

    private func addSystemTransitionObserver(center: NotificationCenter, name: Notification.Name) {
        let observer = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.name.rawValue
            Task { @MainActor in
                self?.scheduleSystemTransitionRecovery(reason: reason)
            }
        }
        systemTransitionObservers.append((center, observer))
    }

    private func scheduleSystemTransitionRecovery(reason: String) {
        systemTransitionRecoveryWorkItems.forEach { $0.cancel() }
        systemTransitionRecoveryWorkItems.removeAll()

        for delay in [0.35, 1.2] {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.recoverWallpaperAfterSystemTransition(reason: reason)
                }
            }
            systemTransitionRecoveryWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func recoverWallpaperAfterSystemTransition(reason: String) {
        guard isRunning else {
            return
        }

        if performancePolicy == .keepRunning {
            isSuspended = false
            manager.resume()
        } else {
            evaluatePerformancePolicy()
        }

        manager.recoverAfterSystemTransition()
        NSLog("[MotionDock Wallpaper] requested system transition recovery after %@", reason)
    }

    private var isLowPowerAndBatterySaver: Bool {
        performanceProfile == .batterySaver && ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func saveLibrary() {
        guard let data = try? JSONEncoder().encode(libraryItems) else {
            return
        }
        UserDefaults.standard.set(data, forKey: DefaultsKey.libraryItems)
    }

    private static func loadLibrary(from defaults: UserDefaults) -> [WallpaperLibraryItem] {
        guard
            let data = defaults.data(forKey: DefaultsKey.libraryItems),
            let decoded = try? JSONDecoder().decode([WallpaperLibraryItem].self, from: data),
            !decoded.isEmpty
        else {
            return WallpaperLibraryItem.defaults
        }

        let validItems = decoded.filter { item in
            switch item.kind {
            case .motion, .video, .gif:
                return true
            case .web:
                guard let urlString = item.webURLString, let url = URL(string: urlString) else {
                    return false
                }
                return Self.isSupportedWebURL(url)
            }
        }

        let missingBuiltIns = WallpaperLibraryItem.defaults.filter { defaultItem in
            !validItems.contains { $0.id == defaultItem.id }
        }
        return missingBuiltIns + validItems
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https":
            return url.host?.isEmpty == false
        case "file":
            return !url.path.isEmpty
        default:
            return false
        }
    }

    private static func isGIFFile(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "gif" {
            return true
        }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .gif) ?? false
    }

    private static func frontmostApplicationCoversDisplay() -> Bool {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let ignoredBundleIDs = [
            Bundle.main.bundleIdentifier,
            "com.apple.finder",
            "com.apple.dock"
        ].compactMap { $0 }

        if ignoredBundleIDs.contains(frontmostApplication.bundleIdentifier ?? "") {
            return false
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let pid = frontmostApplication.processIdentifier
        let screenFrames = NSScreen.screens.map(\.frame)

        for window in windowList {
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == pid,
                window[kCGWindowLayer as String] as? Int == 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else {
                continue
            }

            for screenFrame in screenFrames {
                let intersection = bounds.intersection(screenFrame)
                guard !intersection.isNull else {
                    continue
                }

                let coverage = (intersection.width * intersection.height) / (screenFrame.width * screenFrame.height)
                if coverage > 0.78 {
                    return true
                }
            }
        }

        return false
    }

    private func schedule(_ operation: @escaping @MainActor (AppModel) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                operation(self)
            }
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

private struct LastWallpaperRecord: Codable {
    let id: String
    let name: String
    let kindRawValue: String
    let videoPath: String?
    let webURLString: String?
    let motionSceneRawValue: String
    let motionPaletteRawValue: String
    let isBuiltIn: Bool
    let uploaderID: String?

    init(item: WallpaperLibraryItem) {
        id = item.id
        name = item.name
        kindRawValue = item.kind.rawValue
        videoPath = item.videoPath
        webURLString = item.webURLString
        motionSceneRawValue = item.motionScene.rawValue
        motionPaletteRawValue = item.motionPalette.rawValue
        isBuiltIn = item.isBuiltIn
        uploaderID = item.uploaderID
    }

    var libraryItem: WallpaperLibraryItem? {
        guard
            let kind = WallpaperItemKind(rawValue: kindRawValue),
            let motionScene = MotionScene(rawValue: motionSceneRawValue),
            let motionPalette = MotionPalette(rawValue: motionPaletteRawValue)
        else {
            return nil
        }

        return WallpaperLibraryItem(
            id: id,
            name: name,
            kind: kind,
            videoPath: videoPath,
            webURLString: webURLString,
            motionScene: motionScene,
            motionPalette: motionPalette,
            isBuiltIn: isBuiltIn,
            uploaderID: uploaderID
        )
    }
}

private enum DefaultsKey {
    static let libraryItems = "libraryItems"
    static let selectedItemID = "selectedItemID"
    static let playlistEnabled = "playlistEnabled"
    static let playlistIntervalMinutes = "playlistIntervalMinutes"
    static let displayMode = "displayMode"
    static let performanceProfile = "performanceProfile"
    static let performancePolicy = "performancePolicy"
    static let marketplaceServerURLString = "marketplaceServerURLString"
    static let favoriteItemIDs = "favoriteItemIDs"
    static let isMuted = "isMuted"
    static let fillMode = "fillMode"
    static let startAtLoginEnabled = "startAtLoginEnabled"
    static let showInDock = "showInDock"
    static let lastWallpaperRecord = "lastWallpaperRecord"
}
