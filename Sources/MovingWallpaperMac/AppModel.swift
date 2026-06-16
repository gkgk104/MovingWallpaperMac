import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
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
    @Published var profileDisplayName: String {
        didSet {
            UserDefaults.standard.set(profileDisplayName, forKey: DefaultsKey.profileDisplayName)
        }
    }
    @Published var profileHandle: String {
        didSet {
            UserDefaults.standard.set(profileHandle, forKey: DefaultsKey.profileHandle)
        }
    }
    @Published var profileIsLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(profileIsLoggedIn, forKey: DefaultsKey.profileIsLoggedIn)
        }
    }
    @Published private(set) var profileID: String
    @Published var profileMessage: String?
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

    private let manager = WallpaperManager()
    private var playlistTimer: Timer?
    private var performanceTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var suppressAutomaticRestart = false

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

    var profileDisplayText: String {
        let displayName = normalizedProfileDisplayName
        let handle = normalizedProfileHandle

        guard !displayName.isEmpty else {
            return "Sign in required"
        }

        return handle.isEmpty ? displayName : "\(displayName) (@\(handle))"
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
        profileDisplayName = defaults.string(forKey: DefaultsKey.profileDisplayName) ?? ""
        profileHandle = defaults.string(forKey: DefaultsKey.profileHandle) ?? ""
        profileIsLoggedIn = defaults.object(forKey: DefaultsKey.profileIsLoggedIn) as? Bool ?? false
        profileID = Self.loadProfileID(from: defaults)
        favoriteItemIDs = Set(defaults.stringArray(forKey: DefaultsKey.favoriteItemIDs) ?? [])

        NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.evaluatePerformancePolicy()
                }
            }
            .store(in: &cancellables)
    }

    var canUploadSelectedItem: Bool {
        guard let selectedItem, selectedItem.isBuiltIn == false else {
            return false
        }
        return selectedItem.kind == .video || selectedItem.kind == .gif
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

    func uploadSelectedItemToMarketplace() {
        Task { @MainActor in
            await uploadSelectedItemToMarketplaceNow()
        }
    }

    func downloadMarketplaceItem(_ item: MarketplaceItem, apply: Bool) {
        Task { @MainActor in
            await downloadMarketplaceItemNow(item, apply: apply)
        }
    }

    func signInProfile() {
        schedule { model in
            let displayName = model.normalizedProfileDisplayName
            guard !displayName.isEmpty else {
                model.profileMessage = "Enter a display name."
                return
            }

            model.profileDisplayName = displayName
            model.profileHandle = model.normalizedProfileHandle
            model.profileIsLoggedIn = true
            model.profileMessage = "Profile is active."
        }
    }

    func signOutProfile() {
        schedule { model in
            model.profileIsLoggedIn = false
            model.profileMessage = "Profile signed out."
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

    private func removeSelectedItemNow() {
        guard removableSelection, let selectedItem else {
            return
        }

        libraryItems.removeAll { $0.id == selectedItem.id }
        setSelectedItem(libraryItems.first?.id ?? WallpaperLibraryItem.defaults[0].id, restart: false)
        restartNowIfRunning()
    }

    func updateSelectedMotionScene(_ scene: MotionScene) {
        schedule { model in
            model.updateSelectedItem { $0.motionScene = scene }
            model.restartNowIfRunning()
        }
    }

    func updateSelectedMotionPalette(_ palette: MotionPalette) {
        schedule { model in
            model.updateSelectedItem { $0.motionPalette = palette }
            model.restartNowIfRunning()
        }
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

    private func stopNow() {
        manager.stop()
        isRunning = false
        isSuspended = false
        playlistTimer?.invalidate()
        playlistTimer = nil
        performanceTimer?.invalidate()
        performanceTimer = nil
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

    func bindingForSelectedScene() -> Binding<MotionScene> {
        Binding {
            self.selectedItem?.motionScene ?? .aurora
        } set: { scene in
            self.updateSelectedMotionScene(scene)
        }
    }

    func bindingForSelectedPalette() -> Binding<MotionPalette> {
        Binding {
            self.selectedItem?.motionPalette ?? .aurora
        } set: { palette in
            self.updateSelectedMotionPalette(palette)
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
        guard let baseURL = marketplaceBaseURL else {
            marketplaceMessage = MarketplaceError.invalidServerURL.localizedDescription
            return
        }

        marketplaceIsLoading = true
        marketplaceMessage = nil
        defer { marketplaceIsLoading = false }

        do {
            let listURL = baseURL.appendingPathComponent("api/wallpapers")
            let (data, response) = try await URLSession.shared.data(from: listURL)
            try validate(response: response, data: data)
            marketplaceItems = try JSONDecoder().decode([MarketplaceItem].self, from: data)
            marketplaceMessage = marketplaceItems.isEmpty ? "No marketplace wallpapers yet." : nil
        } catch {
            marketplaceMessage = error.localizedDescription
        }
    }

    private func uploadSelectedItemToMarketplaceNow() async {
        guard let baseURL = marketplaceBaseURL else {
            marketplaceMessage = MarketplaceError.invalidServerURL.localizedDescription
            return
        }
        guard profileIsLoggedIn else {
            marketplaceMessage = "Sign in from Profiles before uploading."
            return
        }
        guard let selectedItem, selectedItem.kind == .video || selectedItem.kind == .gif else {
            marketplaceMessage = MarketplaceError.unsupportedUpload.localizedDescription
            return
        }
        guard let path = selectedItem.videoPath, FileManager.default.fileExists(atPath: path) else {
            marketplaceMessage = MarketplaceError.missingLocalFile.localizedDescription
            return
        }

        marketplaceIsLoading = true
        marketplaceMessage = "Uploading..."
        defer { marketplaceIsLoading = false }

        do {
            let fileURL = URL(fileURLWithPath: path)
            let uploadURL = baseURL.appendingPathComponent("api/wallpapers")
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"

            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let body = try multipartBody(
                boundary: boundary,
                fields: [
                    "title": selectedItem.name,
                    "kind": selectedItem.kind == .gif ? "gif" : "video",
                    "uploaderName": profileDisplayText,
                    "uploaderID": profileID
                ],
                fileField: "file",
                fileURL: fileURL
            )

            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            try validate(response: response, data: data)
            marketplaceMessage = "Upload complete."
            await refreshMarketplaceNow()
        } catch {
            marketplaceMessage = error.localizedDescription
        }
    }

    private func downloadMarketplaceItemNow(_ item: MarketplaceItem, apply: Bool) async {
        guard let baseURL = marketplaceBaseURL else {
            marketplaceMessage = MarketplaceError.invalidServerURL.localizedDescription
            return
        }
        guard let kind = item.supportedKind else {
            marketplaceMessage = MarketplaceError.unsupportedDownload.localizedDescription
            return
        }
        guard let downloadURL = URL(string: item.downloadURL, relativeTo: baseURL)?.absoluteURL else {
            marketplaceMessage = MarketplaceError.invalidResponse.localizedDescription
            return
        }

        marketplaceBusyItemID = item.id
        marketplaceMessage = apply ? "Downloading and applying..." : "Downloading..."
        defer { marketplaceBusyItemID = nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            try validate(response: response, data: data)

            let savedURL = try saveDownloadedMarketplaceFile(data: data, item: item)
            let libraryItem = WallpaperLibraryItem(
                id: "marketplace-\(item.id)",
                name: item.title,
                kind: kind,
                videoPath: savedURL.path,
                webURLString: nil,
                motionScene: .aurora,
                motionPalette: .aurora,
                isBuiltIn: false
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

    private var marketplaceBaseURL: URL? {
        let trimmed = marketplaceServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil, components.host != nil else {
            return nil
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url
    }

    private var normalizedProfileDisplayName: String {
        profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedProfileHandle: String {
        profileHandle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private var selectedLocalFileURL: URL? {
        guard let path = selectedItem?.videoPath, !path.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func saveDownloadedMarketplaceFile(data: Data, item: MarketplaceItem) throws -> URL {
        let directory = try marketplaceDownloadsDirectory()
        let filename = safeFilename("\(item.id)-\(item.filename)")
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
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
        case "webm":
            return "video/webm"
        case "avi":
            return "video/x-msvideo"
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

    private static func loadProfileID(from defaults: UserDefaults) -> String {
        if let savedID = defaults.string(forKey: DefaultsKey.profileID), !savedID.isEmpty {
            return savedID
        }

        let generatedID = UUID().uuidString
        defaults.set(generatedID, forKey: DefaultsKey.profileID)
        return generatedID
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

private enum DefaultsKey {
    static let libraryItems = "libraryItems"
    static let selectedItemID = "selectedItemID"
    static let playlistEnabled = "playlistEnabled"
    static let playlistIntervalMinutes = "playlistIntervalMinutes"
    static let displayMode = "displayMode"
    static let performanceProfile = "performanceProfile"
    static let performancePolicy = "performancePolicy"
    static let marketplaceServerURLString = "marketplaceServerURLString"
    static let profileDisplayName = "profileDisplayName"
    static let profileHandle = "profileHandle"
    static let profileIsLoggedIn = "profileIsLoggedIn"
    static let profileID = "profileID"
    static let favoriteItemIDs = "favoriteItemIDs"
    static let isMuted = "isMuted"
    static let fillMode = "fillMode"
}
