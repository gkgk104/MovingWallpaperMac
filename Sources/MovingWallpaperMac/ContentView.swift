import AppKit
import SwiftUI

enum MotionDockLayout {
    static let sidebarWidth: CGFloat = 230
    static let inspectorWidth: CGFloat = 340
    static let inspectorHorizontalPadding: CGFloat = 24
    static let inspectorVerticalPadding: CGFloat = 24
    static let inspectorContentWidth: CGFloat = inspectorWidth - inspectorHorizontalPadding * 2
    static let inspectorInfoLabelWidth: CGFloat = 86
    static let inspectorInfoColumnSpacing: CGFloat = 12
    static let inspectorInfoValueWidth: CGFloat = inspectorContentWidth - inspectorInfoLabelWidth - inspectorInfoColumnSpacing
    static let dividerWidth: CGFloat = 1
    static let minMainWidth: CGFloat = 560
    static let minimumWindowWidth: CGFloat = sidebarWidth + minMainWidth + dividerWidth
    static let minimumWindowHeight: CGFloat = 640
    static let idealWindowWidth: CGFloat = 1320
    static let idealWindowHeight: CGFloat = 720
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @StateObject private var thumbnailStore = WallpaperThumbnailStore()
    @State private var selectedSection: SidebarSection = .library
    @State private var selectedItemID: String
    @State private var searchText = ""
    @State private var isURLImportPresented = false
    @State private var playlistEnabled: Bool
    @State private var playlistIntervalMinutes: Double
    @State private var displayMode: DisplayMode
    @State private var performanceProfile: PerformanceProfile
    @State private var performancePolicy: PerformancePolicy
    @State private var startAtLoginEnabled: Bool
    @State private var isMuted: Bool
    @State private var fillMode: VideoFillMode

    init(model: AppModel) {
        self.model = model
        _selectedItemID = State(initialValue: model.selectedItemID)
        _playlistEnabled = State(initialValue: model.playlistEnabled)
        _playlistIntervalMinutes = State(initialValue: model.playlistIntervalMinutes)
        _displayMode = State(initialValue: model.displayMode)
        _performanceProfile = State(initialValue: model.performanceProfile)
        _performancePolicy = State(initialValue: model.performancePolicy)
        _startAtLoginEnabled = State(initialValue: model.startAtLoginEnabled)
        _isMuted = State(initialValue: model.isMuted)
        _fillMode = State(initialValue: model.fillMode)
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = MotionDockLayout.sidebarWidth
            let detailWidth = MotionDockLayout.inspectorWidth
            let dividerWidth = MotionDockLayout.dividerWidth
            let minMainWidth = MotionDockLayout.minMainWidth
            let minWindowWidthForDetail = sidebarWidth + minMainWidth + detailWidth + dividerWidth * 2
            let shouldShowDetail = model.selectedItem != nil && proxy.size.width >= minWindowWidthForDetail
            let calculatedMainWidth = proxy.size.width
                - sidebarWidth
                - (shouldShowDetail ? detailWidth : 0)
                - dividerWidth * (shouldShowDetail ? 2 : 1)
            let mainWidth = max(
                minMainWidth,
                calculatedMainWidth
            )

            HStack(spacing: 0) {
                MotionDockSidebar(
                    selection: $selectedSection,
                    libraryCount: model.libraryItems.count,
                    collectionCount: collectionItems.count,
                    favoriteCount: model.favoriteItemIDs.count,
                    recentCount: recentlyAddedItems.count,
                    isRunning: model.isRunning
                )
                .frame(width: sidebarWidth, height: proxy.size.height)
                .clipped()

                MotionDockDivider()
                    .frame(width: dividerWidth, height: proxy.size.height)

                mainContent
                    .frame(width: mainWidth, height: proxy.size.height)
                    .clipped()

                if shouldShowDetail {
                    MotionDockDivider()
                        .frame(width: dividerWidth, height: proxy.size.height)

                    inspectorPanel
                        .frame(width: detailWidth, height: proxy.size.height)
                        .clipped()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .frame(
            minWidth: MotionDockLayout.minimumWindowWidth,
            maxWidth: .infinity,
            minHeight: MotionDockLayout.minimumWindowHeight,
            maxHeight: .infinity
        )
        .clipped()
        .background {
            MotionDockAmbientBackground()
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .sheet(isPresented: $isURLImportPresented) {
            URLImportSheet(
                urlString: $model.webURLDraft,
                onCancel: {
                    model.webURLDraft = ""
                    isURLImportPresented = false
                },
                onImport: {
                    model.addWebsite()
                    isURLImportPresented = false
                    selectedSection = .library
                }
            )
        }
        .onReceive(model.$selectedItemID) { value in
            if selectedItemID != value {
                selectedItemID = value
            }
        }
        .onReceive(model.$playlistEnabled) { value in
            if playlistEnabled != value {
                playlistEnabled = value
            }
        }
        .onReceive(model.$playlistIntervalMinutes) { value in
            if playlistIntervalMinutes != value {
                playlistIntervalMinutes = value
            }
        }
        .onReceive(model.$displayMode) { value in
            if displayMode != value {
                displayMode = value
            }
        }
        .onReceive(model.$performanceProfile) { value in
            if performanceProfile != value {
                performanceProfile = value
            }
        }
        .onReceive(model.$performancePolicy) { value in
            if performancePolicy != value {
                performancePolicy = value
            }
        }
        .onReceive(model.$startAtLoginEnabled) { value in
            if startAtLoginEnabled != value {
                startAtLoginEnabled = value
            }
        }
        .onReceive(model.$settingsRequestCounter) { _ in
            withAnimation(MotionDockTheme.animation) {
                selectedSection = .settings
            }
        }
        .onReceive(model.$isMuted) { value in
            if isMuted != value {
                isMuted = value
            }
        }
        .onReceive(model.$fillMode) { value in
            if fillMode != value {
                fillMode = value
            }
        }
    }

    private var inspectorPanel: some View {
        InspectorPanel(
            model: model,
            thumbnailStore: thumbnailStore,
            item: model.selectedItem,
            isFavorite: model.selectedItem.map(model.isFavorite) ?? false,
            onStart: model.start,
            onStop: model.stop,
            onReveal: model.revealSelectedInFinder,
            onFavorite: {
                if let item = model.selectedItem {
                    model.toggleFavorite(item)
                }
            },
            onRemove: model.removeSelectedItem
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedSection {
        case .library, .collections, .favorites, .recentlyAdded:
            wallpaperGridPage
                .transition(.opacity)
        case .discover:
            placeholderPage(
                icon: "sparkles.rectangle.stack",
                title: "Discover",
                message: "Discover curated motion wallpapers soon."
            )
            .transition(.opacity)
        case .profiles:
            profilesPage
                .transition(.opacity)
        case .settings:
            settingsPage
                .transition(.opacity)
        }
    }

    private var wallpaperGridPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader(
                title: selectedSection.title,
                subtitle: selectedSection.subtitle,
                showsImport: true
            )

            if let errorMessage = model.errorMessage {
                MessageBanner(message: errorMessage, style: .error)
                    .transition(.opacity)
            }

            if filteredWallpapers.isEmpty {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "No search results",
                        message: "Try a different title, file name, or format."
                    )
                } else {
                    emptyState(
                        icon: "rectangle.stack.badge.plus",
                        title: selectedSection.emptyTitle,
                        message: selectedSection.emptyMessage
                    )
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: wallpaperColumns, alignment: .leading, spacing: 18) {
                        ForEach(filteredWallpapers) { item in
                            WallpaperCard(
                                item: item,
                                thumbnailStore: thumbnailStore,
                                isSelected: item.id == selectedItemID,
                                isRunning: item.id == model.selectedItem?.id && model.isRunning,
                                isFavorite: model.isFavorite(item),
                                onSelect: {
                                    withAnimation(MotionDockTheme.animation) {
                                        selectedItemID = item.id
                                        model.selectItem(item.id)
                                    }
                                },
                                onFavorite: {
                                    model.toggleFavorite(item)
                                }
                            )
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            MotionDockAmbientBackground()
        }
        .animation(MotionDockTheme.animation, value: selectedSection)
        .animation(MotionDockTheme.animation, value: filteredWallpapers.map(\.id))
    }

    private var profilesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader(
                title: "Profiles",
                subtitle: "Use a local profile to identify your uploads and personalize MotionDock.",
                showsImport: false
            )

            if !model.profileIsLoggedIn {
                emptyState(
                    icon: "person.crop.circle.badge.plus",
                    title: "Profiles",
                    message: "Create a local profile to attach your name to uploaded wallpapers."
                )
                .frame(maxHeight: 220)
            }

            PremiumPanel {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader("Local Profile")

                    InspectorInfoRow(label: "Status") {
                        StatusPill(text: model.profileIsLoggedIn ? "Running" : "Stopped", isRunning: model.profileIsLoggedIn)
                    }

                    LabeledControl(title: "Display Name") {
                        MotionDockTextField("Display name", text: $model.profileDisplayName)
                            .frame(maxWidth: 360)
                    }

                    LabeledControl(title: "Handle") {
                        HStack(spacing: 6) {
                            Text("@")
                                .foregroundStyle(MotionDockTheme.secondaryText)
                            MotionDockTextField("handle", text: $model.profileHandle)
                                .frame(maxWidth: 260)
                        }
                    }

                    InspectorInfoRow(label: "Uploader") {
                        Text(model.profileDisplayText)
                            .foregroundStyle(model.profileIsLoggedIn ? Color.white.opacity(0.92) : MotionDockTheme.secondaryText)
                            .lineLimit(1)
                    }

                    InspectorInfoRow(label: "Profile ID") {
                        Text(model.profileID)
                            .font(.caption.monospaced())
                            .foregroundStyle(MotionDockTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    if let message = model.profileMessage {
                        MessageBanner(message: message, style: message.contains("Enter") ? .error : .neutral)
                    }

                    HStack(spacing: 10) {
                        Button {
                            model.signInProfile()
                        } label: {
                            Label(model.profileIsLoggedIn ? "Update Profile" : "Create Profile", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(MotionDockPrimaryButtonStyle())

                        Button {
                            model.signOutProfile()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(MotionDockSecondaryButtonStyle())
                        .disabled(!model.profileIsLoggedIn)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            MotionDockAmbientBackground()
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Settings",
                    subtitle: "Tune playback, performance, and advanced library behavior.",
                    showsImport: false
                )

                brandSettings

                PremiumPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader("Playback")

                        LabeledControl(title: "Display") {
                            MotionDockSegmentedPicker(
                                options: DisplayMode.allCases,
                                selection: $displayMode,
                                title: { $0.label }
                            )
                            .frame(maxWidth: 360)
                            .onChange(of: displayMode) { newValue in
                                model.setDisplayMode(newValue)
                            }
                        }

                        LabeledControl(title: "Audio") {
                            Toggle("Mute video and web wallpapers", isOn: $isMuted)
                                .toggleStyle(.switch)
                                .onChange(of: isMuted) { newValue in
                                    model.setMuted(newValue)
                                }
                        }

                        LabeledControl(title: "Scale") {
                            MotionDockSegmentedPicker(
                                options: VideoFillMode.allCases,
                                selection: $fillMode,
                                title: { $0.label }
                            )
                            .frame(maxWidth: 220)
                            .onChange(of: fillMode) { newValue in
                                model.setFillMode(newValue)
                            }
                        }

                        LabeledControl(title: "Playlist") {
                            HStack(spacing: 14) {
                                Toggle("Cycle wallpapers", isOn: $playlistEnabled)
                                    .toggleStyle(.switch)
                                    .onChange(of: playlistEnabled) { newValue in
                                        model.setPlaylistEnabled(newValue)
                                    }

                                MotionDockIntervalStepper(
                                    value: $playlistIntervalMinutes,
                                    in: 1...120,
                                    step: 1
                                )
                                .disabled(!playlistEnabled)
                                .onChange(of: playlistIntervalMinutes) { newValue in
                                    model.setPlaylistIntervalMinutes(newValue)
                                }
                            }
                        }
                    }
                }

                PremiumPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader("Performance")

                        LabeledControl(title: "Profile") {
                            MotionDockSegmentedPicker(
                                options: PerformanceProfile.allCases,
                                selection: $performanceProfile,
                                title: { $0.label }
                            )
                            .frame(maxWidth: 360)
                            .onChange(of: performanceProfile) { newValue in
                                model.setPerformanceProfile(newValue)
                            }
                        }

                        LabeledControl(title: "Policy") {
                            MotionDockOptionMenu(
                                options: PerformancePolicy.allCases,
                                selection: $performancePolicy,
                                title: { $0.label }
                            )
                            .frame(maxWidth: 320)
                            .onChange(of: performancePolicy) { newValue in
                                model.setPerformancePolicy(newValue)
                            }
                        }
                    }
                }

                systemSettings

                marketplaceSettings
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
        }
        .scrollContentBackground(.hidden)
        .background {
            MotionDockAmbientBackground()
        }
    }

    private var brandSettings: some View {
        PremiumPanel {
            HStack(alignment: .center, spacing: 18) {
                MotionDockLogoView(size: 74)

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("About")

                    Text(MotionDockBrand.appName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)

                    Text(MotionDockBrand.tagline)
                        .font(.callout)
                        .foregroundStyle(MotionDockTheme.secondaryText)

                    Text("Dock Wave")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MotionDockTheme.cyanHighlight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(MotionDockTheme.cyanHighlight.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var systemSettings: some View {
        PremiumPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader("System")

                LabeledControl(title: "Login") {
                    Toggle("Start MotionDock when I log in", isOn: $startAtLoginEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: startAtLoginEnabled) { newValue in
                            model.setStartAtLoginEnabled(newValue)
                        }
                }

                if let message = model.loginItemMessage {
                    MessageBanner(
                        message: message,
                        style: message.localizedCaseInsensitiveContains("failed") ? .error : .neutral
                    )
                }
            }
        }
    }

    private var marketplaceSettings: some View {
        PremiumPanel {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Self-hosted Marketplace")

                LabeledControl(title: "Server") {
                    MotionDockTextField("http://127.0.0.1:8787", text: $model.marketplaceServerURLString)
                        .frame(maxWidth: 420)
                }

                HStack(spacing: 10) {
                    Button {
                        model.refreshMarketplace()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MotionDockSecondaryButtonStyle())
                    .disabled(model.marketplaceIsLoading)

                    Button {
                        model.uploadSelectedItemToMarketplace()
                    } label: {
                        Label("Upload Selected", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(MotionDockSecondaryButtonStyle())
                    .disabled(!model.canUploadSelectedItem || !model.profileIsLoggedIn || model.marketplaceIsLoading)
                }

                if let message = model.marketplaceMessage {
                    MessageBanner(message: message, style: message.contains("error") || message.contains("invalid") ? .error : .neutral)
                }

                if !model.marketplaceItems.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(model.marketplaceItems.prefix(4)) { item in
                            MarketplaceCompactRow(
                                item: item,
                                isBusy: model.marketplaceBusyItemID == item.id,
                                onDownload: {
                                    model.downloadMarketplaceItem(item, apply: false)
                                    selectedSection = .library
                                },
                                onApply: {
                                    model.downloadMarketplaceItem(item, apply: true)
                                    selectedSection = .library
                                }
                            )

                            if item.id != model.marketplaceItems.prefix(4).last?.id {
                                MotionDockDivider(axis: .horizontal)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MotionDockTheme.border, lineWidth: 1)
                    }
                }
            }
        }
    }

    private func pageHeader(title: String, subtitle: String, showsImport: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white)
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineLimit(2)
            }
            .frame(minWidth: 220, alignment: .leading)
            .layoutPriority(1)

            if showsImport {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        searchField
                            .frame(maxWidth: 300)

                        Spacer(minLength: 12)

                        importControl
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        searchField
                            .frame(maxWidth: 300)

                        importControl
                    }
                }
            }
        }
    }

    private var importControl: some View {
        ImportWallpaperControl(
            onImportFiles: {
                model.addMediaFiles()
                selectedSection = .library
            },
            onImportURL: {
                isURLImportPresented = true
            }
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MotionDockTheme.secondaryText)
            ZStack(alignment: .leading) {
                if searchText.isEmpty {
                    Text("Search wallpapers")
                        .foregroundStyle(MotionDockTheme.secondaryText.opacity(0.78))
                        .lineLimit(1)
                }

                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.92))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(MotionDockTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
    }

    private func placeholderPage(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader(title: title, subtitle: "Live wallpapers, made native for macOS.", showsImport: false)

            emptyState(icon: icon, title: title, message: message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            MotionDockAmbientBackground()
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        EmptyStateView(icon: icon, title: title, message: message)
    }

    private var wallpaperColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 18)
        ]
    }

    private var recentlyAddedItems: [WallpaperLibraryItem] {
        model.libraryItems.filter { !$0.isBuiltIn }
    }

    private var collectionItems: [WallpaperLibraryItem] {
        model.libraryItems.filter { $0.kind == .motion }
    }

    private var sectionItems: [WallpaperLibraryItem] {
        switch selectedSection {
        case .library:
            return model.libraryItems
        case .collections:
            return collectionItems
        case .favorites:
            return model.libraryItems.filter { model.isFavorite($0) }
        case .recentlyAdded:
            return recentlyAddedItems
        case .discover, .profiles, .settings:
            return []
        }
    }

    private var filteredWallpapers: [WallpaperLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return sectionItems
        }

        return sectionItems.filter { item in
            item.name.lowercased().contains(query)
                || item.detail.lowercased().contains(query)
                || item.kind.label.lowercased().contains(query)
        }
    }
}

private enum SidebarSection: String, CaseIterable, Identifiable {
    case library
    case collections
    case favorites
    case recentlyAdded
    case discover
    case profiles
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return "Library"
        case .collections:
            return "Collections"
        case .favorites:
            return "Favorites"
        case .recentlyAdded:
            return "Recently Added"
        case .discover:
            return "Discover"
        case .profiles:
            return "Profiles"
        case .settings:
            return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .library:
            return "Live wallpapers, made native for macOS."
        case .collections:
            return "Built-in motion wallpaper collections."
        case .favorites:
            return "Your saved wallpapers."
        case .recentlyAdded:
            return "The wallpapers you imported most recently."
        case .discover:
            return "Curated wallpapers are coming soon."
        case .profiles:
            return "Manage the profile attached to uploads."
        case .settings:
            return "Playback, performance, and advanced options."
        }
    }

    var emptyTitle: String {
        switch self {
        case .collections:
            return "No collections"
        case .favorites:
            return "No favorites yet"
        case .recentlyAdded:
            return "No wallpapers"
        default:
            return "No wallpapers"
        }
    }

    var emptyMessage: String {
        switch self {
        case .collections:
            return "Built-in MotionDock collections will appear here."
        case .favorites:
            return "Add wallpapers to Favorites from the inspector panel."
        case .recentlyAdded:
            return "Import an MP4, MOV, or GIF to see it here."
        default:
            return "Import an MP4, MOV, or GIF to start building your library."
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            return "rectangle.stack"
        case .collections:
            return "square.grid.2x2"
        case .favorites:
            return "star"
        case .recentlyAdded:
            return "clock"
        case .discover:
            return "sparkles"
        case .profiles:
            return "person.crop.circle"
        case .settings:
            return "gearshape"
        }
    }
}

private struct MotionDockSidebar: View {
    @Binding var selection: SidebarSection
    let libraryCount: Int
    let collectionCount: Int
    let favoriteCount: Int
    let recentCount: Int
    let isRunning: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            MotionDockTheme.secondarySurface

            VStack(alignment: .leading, spacing: 22) {
                MotionDockWordmarkImage()
                    .frame(width: 194, height: 52, alignment: .leading)
                    .clipped()
                .padding(.top, 24)

                VStack(spacing: 8) {
                    sidebarButton(.library, count: libraryCount)
                    sidebarButton(.collections, count: collectionCount)
                    sidebarButton(.favorites, count: favoriteCount)
                    sidebarButton(.recentlyAdded, count: recentCount)
                }

                MotionDockDivider(axis: .horizontal)

                VStack(spacing: 8) {
                    sidebarButton(.discover)
                    sidebarButton(.profiles)
                    sidebarButton(.settings)
                }

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(isRunning ? MotionDockTheme.success : MotionDockTheme.secondaryText.opacity(0.52))
                        .frame(width: 7, height: 7)
                    Text(isRunning ? "Running" : "Ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MotionDockTheme.secondaryText)
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: MotionDockLayout.sidebarWidth,
            idealWidth: MotionDockLayout.sidebarWidth,
            maxWidth: MotionDockLayout.sidebarWidth
        )
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .animation(MotionDockTheme.animation, value: selection)
    }

    private func sidebarButton(_ item: SidebarSection, count: Int? = nil) -> some View {
        MotionDockSidebarItem(
            title: item.title,
            systemImage: item.systemImage,
            count: count,
            isSelected: selection == item,
            action: {
                withAnimation(MotionDockTheme.animation) {
                    selection = item
                }
            }
        )
    }

}

private struct WallpaperCard: View {
    let item: WallpaperLibraryItem
    @ObservedObject var thumbnailStore: WallpaperThumbnailStore
    let isSelected: Bool
    let isRunning: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            MotionDockCard(isSelected: isSelected, isInteractive: isHovered) {
                VStack(alignment: .leading, spacing: 12) {
                    WallpaperCardPreview(item: item, thumbnail: thumbnailStore.thumbnail(for: item))
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 6) {
                                MetadataBadge(WallpaperMetadata.fileType(for: item))
                                MetadataBadge(WallpaperMetadata.resolution(for: item))
                            }
                            .padding(12)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button(action: onFavorite) {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isFavorite ? Color.yellow : Color.white.opacity(0.74))
                                    .frame(width: 30, height: 30)
                                    .background(Color.black.opacity(0.22))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                            .opacity(isHovered || isFavorite ? 1 : 0)
                            .animation(MotionDockTheme.animation, value: isHovered)
                        }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.94))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if isRunning {
                                RunningIndicator()
                                    .fixedSize()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()

                        Text(WallpaperMetadata.cardSubtitle(for: item))
                            .font(.caption)
                            .foregroundStyle(MotionDockTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .animation(MotionDockTheme.animation, value: isHovered)
            .animation(MotionDockTheme.animation, value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .clipped()
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            thumbnailStore.requestThumbnail(for: item)
        }
    }
}

private struct WallpaperCardPreview: View {
    let item: WallpaperLibraryItem
    var thumbnail: NSImage?

    var body: some View {
        GeometryReader { proxy in
            WallpaperPreview(item: item, thumbnail: thumbnail)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipped()
    }
}

private struct InspectorPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var thumbnailStore: WallpaperThumbnailStore
    let item: WallpaperLibraryItem?
    let isFavorite: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onReveal: () -> Void
    let onFavorite: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                VStack(alignment: .leading, spacing: 18) {
                    ScrollView(.vertical, showsIndicators: false) {
                        detailContent(for: item)
                            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .topLeading)
                            .padding(.bottom, 4)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .clipped()

                    detailActions
                }
                .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            } else {
                EmptyStateView(
                    icon: "rectangle.stack.badge.plus",
                    title: "No wallpapers",
                    message: "Import Wallpaper to begin."
                )
                .frame(width: MotionDockLayout.inspectorContentWidth)
                .frame(maxHeight: .infinity)
                .clipped()
            }
        }
        .padding(.horizontal, MotionDockLayout.inspectorHorizontalPadding)
        .padding(.vertical, MotionDockLayout.inspectorVerticalPadding)
        .frame(
            width: MotionDockLayout.inspectorWidth,
            alignment: .topLeading
        )
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MotionDockTheme.secondarySurface)
        .clipped()
    }

    private func detailContent(for item: WallpaperLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            WallpaperPreview(item: item, prominent: true, thumbnail: thumbnailStore.thumbnail(for: item))
                .frame(
                    width: MotionDockLayout.inspectorContentWidth,
                    height: MotionDockLayout.inspectorContentWidth * 11.0 / 16.0
                )
                .clipped()
                .onAppear {
                    thumbnailStore.requestThumbnail(for: item)
                }
                .onChange(of: item.id) { _ in
                    thumbnailStore.requestThumbnail(for: item)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                    .clipped()

                StatusPill(text: model.isRunning ? "Running" : "Stopped", isRunning: model.isRunning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
            .clipped()

            VStack(spacing: 12) {
                DetailInfoRow(label: "Resolution", value: WallpaperMetadata.resolution(for: item))
                DetailInfoRow(label: "Duration", value: WallpaperMetadata.duration(for: item))
                DetailInfoRow(label: "File Type", value: WallpaperMetadata.fileType(for: item))
                DetailInfoRow(label: "File Size", value: WallpaperMetadata.fileSize(for: item))
                DetailInfoRow(label: "Added", value: WallpaperMetadata.added(for: item))
                DetailInfoRow(
                    label: "Path",
                    value: WallpaperMetadata.path(for: item),
                    truncationMode: .middle
                )
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
            .clipped()

            if item.kind == .motion {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Motion")
                        .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                        .clipped()

                    Picker("Scene", selection: model.bindingForSelectedScene()) {
                        ForEach(MotionScene.allCases) { scene in
                            Text(scene.label).tag(scene)
                        }
                    }
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                    .clipped()

                    Picker("Palette", selection: model.bindingForSelectedPalette()) {
                        ForEach(MotionPalette.allCases) { palette in
                            Text(palette.label).tag(palette)
                        }
                    }
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                    .clipped()
                }
                .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                .clipped()
            }

            if let errorMessage = model.errorMessage {
                MessageBanner(message: errorMessage, style: .error)
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                    .clipped()
            }
        }
        .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .topLeading)
        .clipped()
    }

    private var detailActions: some View {
        VStack(spacing: 10) {
            DetailActionButton(
                title: model.isRunning ? "Stop Wallpaper" : "Start Wallpaper",
                systemImage: model.isRunning ? "stop.fill" : "play.fill",
                style: .primary,
                isDisabled: !model.isRunning && !model.canStart,
                action: {
                    if model.isRunning {
                        onStop()
                    } else {
                        onStart()
                    }
                }
            )

            DetailActionButton(
                title: "Reveal in Finder",
                systemImage: "folder",
                style: .secondary,
                isDisabled: !model.canRevealSelectedItem,
                action: onReveal
            )

            DetailActionButton(
                title: isFavorite ? "Favorited" : "Add to Favorites",
                systemImage: isFavorite ? "star.fill" : "star",
                style: .secondary,
                action: onFavorite
            )

            if model.removableSelection {
                DetailActionButton(
                    title: "Remove from Library",
                    systemImage: "trash",
                    style: .destructive,
                    action: onRemove
                )
            }
        }
        .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .center)
        .clipped()
    }
}

private struct WallpaperPreview: View {
    let item: WallpaperLibraryItem
    var prominent = false
    var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous)
                .fill(previewGradient)

            if item.kind == .motion {
                ProceduralWallpaperView(
                    scene: item.motionScene,
                    palette: item.motionPalette,
                    performanceProfile: prominent ? .quality : .balanced,
                    isPaused: false
                )
                .allowsHitTesting(false)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.black.opacity(prominent ? 0.22 : 0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))

                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.30)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                previewAccent
                    .clipShape(RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous))

                Image(systemName: item.kind.systemImage)
                    .font(.system(size: prominent ? 44 : 34, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(item.kind == .motion ? 0.18 : 0.34))
                    .shadow(color: Color.black.opacity(0.22), radius: 12, y: 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .animation(MotionDockTheme.animation, value: thumbnail != nil)
    }

    private var previewGradient: LinearGradient {
        switch item.kind {
        case .motion:
            switch item.motionPalette {
            case .aurora:
                return LinearGradient(colors: [Color(hex: 0x1C4FD7), Color(hex: 0x47D7AC), Color(hex: 0x15161A)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .ember:
                return LinearGradient(colors: [Color(hex: 0x2A1210), Color(hex: 0xFF6A3D), Color(hex: 0x15161A)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .graphite:
                return LinearGradient(colors: [Color(hex: 0x30343B), Color(hex: 0x0F1012), Color(hex: 0x6B7280)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .prism:
                return LinearGradient(colors: [Color(hex: 0x0A84FF), Color(hex: 0xBF5AF2), Color(hex: 0x30D158)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .video:
            return LinearGradient(colors: [Color(hex: 0x111827), Color(hex: 0x0A84FF).opacity(0.85), Color(hex: 0x1C1D21)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gif:
            return LinearGradient(colors: [Color(hex: 0x2B124C), Color(hex: 0xBF5AF2), Color(hex: 0x1C1D21)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .web:
            return LinearGradient(colors: [Color(hex: 0x102A43), Color(hex: 0x30D158).opacity(0.78), Color(hex: 0x1C1D21)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var previewAccent: some View {
        switch item.kind {
        case .motion:
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for index in 0..<5 {
                        let progress = (sin(t * 0.45 + Double(index)) + 1) / 2
                        var path = Path()
                        let y = size.height * (0.18 + progress * 0.64)
                        path.move(to: CGPoint(x: -20, y: y))
                        path.addCurve(
                            to: CGPoint(x: size.width + 20, y: size.height - y * 0.55),
                            control1: CGPoint(x: size.width * 0.25, y: y - 70),
                            control2: CGPoint(x: size.width * 0.72, y: y + 80)
                        )
                        context.stroke(path, with: .color(Color.white.opacity(0.12)), lineWidth: prominent ? 3 : 2)
                    }
                }
            }
        default:
            LinearGradient(colors: [Color.white.opacity(0.14), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct ImportWallpaperControl: View {
    let onImportFiles: () -> Void
    let onImportURL: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MotionDockPrimaryButton(title: "Import Wallpaper", systemImage: "plus", action: onImportFiles)
                .frame(width: 190)

            Button(action: onImportURL) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("URL")
                }
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .frame(width: 72)
        }
    }
}

private struct URLImportSheet: View {
    @Binding var urlString: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                MotionDockLogoView(size: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text("URL import")
                        .font(.title2.weight(.semibold))
                    Text("Add a web wallpaper from a direct http or https URL.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("https://example.com", text: $urlString)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Import Wallpaper", action: onImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        MotionDockEmptyStateView(icon: icon, title: title, message: message)
    }
}

private struct PremiumPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        MotionDockCard {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LabeledControl<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(MotionDockTheme.secondaryText)
                .frame(width: 116, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InspectorInfoRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(MotionDockTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96, alignment: .leading)

            content
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct DetailInfoRow: View {
    let label: String
    let value: String
    var truncationMode: Text.TruncationMode = .tail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MotionDockLayout.inspectorInfoColumnSpacing) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(MotionDockTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: MotionDockLayout.inspectorInfoLabelWidth, alignment: .leading)
                .clipped()

            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(truncationMode)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: MotionDockLayout.inspectorInfoValueWidth, alignment: .leading)
                .clipped()
        }
        .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
        .clipped()
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MotionDockTheme.secondaryText)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

private struct MetadataBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.30))
            .clipShape(Capsule())
    }
}

private struct StatusPill: View {
    let text: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? MotionDockTheme.success : Color.white.opacity(0.34))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isRunning ? MotionDockTheme.success : MotionDockTheme.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}

private struct RunningIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(MotionDockTheme.success)
                .frame(width: 6, height: 6)
            Text("Running")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(MotionDockTheme.success)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MotionDockTheme.success.opacity(0.12))
        .clipShape(Capsule())
    }
}

private enum MessageBannerStyle {
    case neutral
    case error
}

private struct MessageBanner: View {
    let message: String
    let style: MessageBannerStyle

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: style == .error ? "exclamationmark.triangle" : "info.circle")
                .frame(width: 18)
            Text(message)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .foregroundStyle(style == .error ? Color.red.opacity(0.95) : MotionDockTheme.secondaryText)
        .padding(12)
        .background((style == .error ? Color.red : Color.white).opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((style == .error ? Color.red : Color.white).opacity(0.12), lineWidth: 1)
        }
    }
}

private enum DetailActionButtonStyle {
    case primary
    case secondary
    case destructive
}

private struct DetailActionButton: View {
    let title: String
    let systemImage: String
    var style: DetailActionButtonStyle = .secondary
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16, alignment: .center)
                    .clipped()

                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .clipped()
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, height: 44, alignment: .center)
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .foregroundStyle(foregroundColor)
        .background {
            ZStack(alignment: .bottom) {
                backgroundColor

                if style == .primary && !isDisabled {
                    LiquidReflectionView(lineCount: 4, amplitude: 3, intensity: 0.72, animated: true)
                        .frame(height: 18)
                        .padding(.horizontal, 18)
                        .offset(y: 4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .clipped()
    }

    private var foregroundColor: Color {
        if isDisabled {
            return Color.white.opacity(0.34)
        }

        switch style {
        case .primary:
            return Color.white
        case .secondary:
            return Color.white.opacity(0.88)
        case .destructive:
            return Color.red.opacity(0.92)
        }
    }

    private var backgroundColor: Color {
        if isDisabled {
            return Color.white.opacity(0.04)
        }

        switch style {
        case .primary:
            return MotionDockTheme.accent
        case .secondary:
            return Color.white.opacity(0.07)
        case .destructive:
            return Color.red.opacity(0.08)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return Color.clear
        case .secondary:
            return MotionDockTheme.border
        case .destructive:
            return Color.red.opacity(0.18)
        }
    }
}

private struct MarketplaceCompactRow: View {
    let item: MarketplaceItem
    let isBusy: Bool
    let onDownload: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.supportedKind?.systemImage ?? "questionmark.square")
                .foregroundStyle(MotionDockTheme.secondaryText)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("by \(item.uploaderDisplayText)")
                    .font(.caption)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if isBusy {
                MotionDockLoadingView(compact: true)
                    .frame(width: 42, height: 22)
            }

            Button("Download", action: onDownload)
                .buttonStyle(.borderless)
                .disabled(isBusy || item.supportedKind == nil)

            Button("Apply", action: onApply)
                .buttonStyle(.borderless)
                .disabled(isBusy || item.supportedKind == nil)
        }
        .padding(12)
        .background(MotionDockTheme.secondarySurface)
    }
}

private struct MotionDockSegmentedPicker<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selection == option

                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : MotionDockTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? MotionDockTheme.accent : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
                }
            }
        }
        .padding(4)
        .frame(minHeight: 38)
        .background(MotionDockTheme.secondarySurface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
        .clipped()
    }
}

private struct MotionDockOptionMenu<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    if selection == option {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title(selection))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .frame(width: 16)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(MotionDockTheme.secondarySurface.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MotionDockTheme.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .clipped()
    }
}

private struct MotionDockIntervalStepper: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double

    @Environment(\.isEnabled) private var isEnabled

    init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double) {
        _value = value
        self.bounds = bounds
        self.step = step
    }

    var body: some View {
        HStack(spacing: 8) {
            stepButton(systemImage: "minus", isDisabled: !canDecrement) {
                updateValue(value - step)
            }

            Text("\(Int(value)) min")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.9 : 0.38))
                .lineLimit(1)
                .monospacedDigit()
                .frame(minWidth: 58)

            stepButton(systemImage: "plus", isDisabled: !canIncrement) {
                updateValue(value + step)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 38)
        .background(MotionDockTheme.secondarySurface.opacity(isEnabled ? 0.9 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
        .clipped()
    }

    private var canDecrement: Bool {
        isEnabled && value > bounds.lowerBound
    }

    private var canIncrement: Bool {
        isEnabled && value < bounds.upperBound
    }

    private func stepButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isDisabled ? MotionDockTheme.secondaryText.opacity(0.34) : Color.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(isDisabled ? 0.03 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func updateValue(_ newValue: Double) {
        value = min(bounds.upperBound, max(bounds.lowerBound, newValue))
    }
}

private struct MotionDockTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(MotionDockTheme.secondaryText.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(MotionDockTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
    }
}

private struct MotionDockDivider: View {
    var axis: Axis = .vertical

    var body: some View {
        Rectangle()
            .fill(MotionDockTheme.border)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

private struct MotionDockPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(MotionDockTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(MotionDockTheme.animation, value: configuration.isPressed)
    }
}

private struct MotionDockSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 0.88 : 0.34))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.white.opacity(isEnabled ? (configuration.isPressed ? 0.12 : 0.07) : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(MotionDockTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(MotionDockTheme.animation, value: configuration.isPressed)
    }
}

private enum WallpaperMetadata {
    static func cardSubtitle(for item: WallpaperLibraryItem) -> String {
        switch item.kind {
        case .motion:
            return resolution(for: item)
        case .video, .gif:
            return fileName(for: item)
        case .web:
            return item.webURLString ?? "Web URL"
        }
    }

    static func fileType(for item: WallpaperLibraryItem) -> String {
        switch item.kind {
        case .motion:
            return "MOTION"
        case .video:
            let ext = localURL(for: item)?.pathExtension.uppercased()
            return ext?.isEmpty == false ? ext ?? "MP4" : "MP4"
        case .gif:
            return "GIF"
        case .web:
            return "WEB"
        }
    }

    static func resolution(for item: WallpaperLibraryItem) -> String {
        if let resolution = parsedResolution(from: [item.name, item.detail]) {
            return resolution
        }

        switch item.kind {
        case .motion:
            switch item.id {
            case "motion-mountain":
                return "5120 x 2880"
            case "motion-nebula":
                return "1920 x 1160"
            default:
                return "3840 x 2160"
            }
        case .web:
            return "Adaptive"
        case .video, .gif:
            return "Source"
        }
    }

    static func duration(for item: WallpaperLibraryItem) -> String {
        switch item.kind {
        case .motion:
            return "Continuous"
        case .video:
            return "Loop"
        case .gif:
            return "Animated loop"
        case .web:
            return "Live"
        }
    }

    static func fileName(for item: WallpaperLibraryItem) -> String {
        switch item.kind {
        case .motion:
            return "Built-in renderer"
        case .video, .gif:
            return localURL(for: item)?.lastPathComponent ?? item.detail
        case .web:
            return item.webURLString ?? "Web URL"
        }
    }

    static func fileSize(for item: WallpaperLibraryItem) -> String {
        switch item.kind {
        case .motion:
            return "Adaptive"
        case .video, .gif:
            guard
                let url = localURL(for: item),
                let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = values.fileSize
            else {
                return "Source"
            }
            return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        case .web:
            return "Live"
        }
    }

    static func added(for item: WallpaperLibraryItem) -> String {
        item.isBuiltIn ? "Built-in" : "Imported"
    }

    static func path(for item: WallpaperLibraryItem) -> String {
        switch item.kind {
        case .motion:
            return "Built-in renderer"
        case .video, .gif:
            return localURL(for: item)?.path ?? item.detail
        case .web:
            return item.webURLString ?? "Web URL"
        }
    }

    static func localURL(for item: WallpaperLibraryItem) -> URL? {
        guard let path = item.videoPath, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func parsedResolution(from values: [String]) -> String? {
        for value in values {
            if let range = value.range(of: #"\d{3,5}x\d{3,5}"#, options: .regularExpression) {
                return String(value[range])
            }
        }
        return nil
    }
}
