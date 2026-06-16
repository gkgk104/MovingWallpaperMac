import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSection: SidebarSection = .library
    @State private var selectedItemID: String
    @State private var searchText = ""
    @State private var isURLImportPresented = false
    @State private var playlistEnabled: Bool
    @State private var playlistIntervalMinutes: Double
    @State private var displayMode: DisplayMode
    @State private var performanceProfile: PerformanceProfile
    @State private var performancePolicy: PerformancePolicy
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
        _isMuted = State(initialValue: model.isMuted)
        _fillMode = State(initialValue: model.fillMode)
    }

    var body: some View {
        HStack(spacing: 0) {
            MotionDockSidebar(
                selection: $selectedSection,
                libraryCount: model.libraryItems.count,
                favoriteCount: model.favoriteItemIDs.count,
                recentCount: recentlyAddedItems.count
            )

            MotionDockDivider()

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            MotionDockDivider()

            InspectorPanel(
                model: model,
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
        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity)
        .background(MotionDockTheme.background)
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
                    LazyVGrid(columns: wallpaperColumns, alignment: .leading, spacing: 22) {
                        ForEach(filteredWallpapers) { item in
                            WallpaperCard(
                                item: item,
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
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MotionDockTheme.background)
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
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MotionDockTheme.background)
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Settings",
                    subtitle: "Tune playback, performance, and advanced library behavior.",
                    showsImport: false
                )

                PremiumPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader("Playback")

                        LabeledControl(title: "Display") {
                            Picker("Display", selection: $displayMode) {
                                ForEach(DisplayMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
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
                            Picker("Scale", selection: $fillMode) {
                                ForEach(VideoFillMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
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

                                Stepper(
                                    "\(Int(playlistIntervalMinutes)) min",
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
                            Picker("Profile", selection: $performanceProfile) {
                                ForEach(PerformanceProfile.allCases) { profile in
                                    Text(profile.label).tag(profile)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                            .onChange(of: performanceProfile) { newValue in
                                model.setPerformanceProfile(newValue)
                            }
                        }

                        LabeledControl(title: "Policy") {
                            Picker("Policy", selection: $performancePolicy) {
                                ForEach(PerformancePolicy.allCases) { policy in
                                    Text(policy.label).tag(policy)
                                }
                            }
                            .frame(maxWidth: 320)
                            .onChange(of: performancePolicy) { newValue in
                                model.setPerformancePolicy(newValue)
                            }
                        }
                    }
                }

                marketplaceSettings
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
        }
        .scrollContentBackground(.hidden)
        .background(MotionDockTheme.background)
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
                VStack(alignment: .leading, spacing: 10) {
                    searchField
                        .frame(maxWidth: 300)

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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MotionDockTheme.secondaryText)
            TextField("Search wallpapers", text: $searchText)
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

    private func placeholderPage(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader(title: title, subtitle: "Live wallpapers, made native for macOS.", showsImport: false)

            emptyState(icon: icon, title: title, message: message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MotionDockTheme.background)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        EmptyStateView(icon: icon, title: title, message: message)
    }

    private var wallpaperColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 180, maximum: 290), spacing: 22)
        ]
    }

    private var recentlyAddedItems: [WallpaperLibraryItem] {
        model.libraryItems.filter { !$0.isBuiltIn }
    }

    private var sectionItems: [WallpaperLibraryItem] {
        switch selectedSection {
        case .library:
            return model.libraryItems
        case .collections:
            return model.libraryItems.filter { $0.kind == .motion }
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
            return "Native motion sets and curated groups."
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
    let favoriteCount: Int
    let recentCount: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            MotionDockTheme.secondarySurface

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MotionDockTheme.accent)
                            Image(systemName: "play.rectangle.on.rectangle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("MotionDock")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.white)
                            Text("Native live wallpapers")
                                .font(.caption)
                                .foregroundStyle(MotionDockTheme.secondaryText)
                        }
                    }

                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    sidebarButton(.library, count: libraryCount)
                    sidebarButton(.collections)
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
                        .fill(MotionDockTheme.success)
                        .frame(width: 7, height: 7)
                    Text("Ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MotionDockTheme.secondaryText)
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 246)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .animation(MotionDockTheme.animation, value: selection)
    }

    private func sidebarButton(_ item: SidebarSection, count: Int? = nil) -> some View {
        Button {
            withAnimation(MotionDockTheme.animation) {
                selection = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(item.title)
                    .font(.callout.weight(.medium))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selection == item ? Color.white.opacity(0.9) : MotionDockTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(selection == item ? 0.16 : 0.06))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(selection == item ? Color.white : MotionDockTheme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selection == item ? Color.white.opacity(0.10) : Color.clear)
            }
            .overlay(alignment: .leading) {
                if selection == item {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MotionDockTheme.accent)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 2)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WallpaperCard: View {
    let item: WallpaperLibraryItem
    let isSelected: Bool
    let isRunning: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                WallpaperPreview(item: item)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
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

                        Spacer()

                        if isRunning {
                            RunningIndicator()
                        }
                    }

                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .background(MotionDockTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: MotionDockTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MotionDockTheme.radius, style: .continuous)
                    .stroke(isSelected ? MotionDockTheme.accent : MotionDockTheme.border, lineWidth: isSelected ? 1.8 : 1)
            }
            .shadow(color: Color.black.opacity(isHovered ? 0.34 : 0.18), radius: isHovered ? 18 : 8, y: isHovered ? 10 : 4)
            .scaleEffect(isHovered ? 1.018 : 1)
            .animation(MotionDockTheme.animation, value: isHovered)
            .animation(MotionDockTheme.animation, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct InspectorPanel: View {
    @ObservedObject var model: AppModel
    let item: WallpaperLibraryItem?
    let isFavorite: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onReveal: () -> Void
    let onFavorite: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let item {
                WallpaperPreview(item: item, prominent: true)
                    .aspectRatio(16.0 / 11.0, contentMode: .fit)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)

                    StatusPill(text: model.isRunning ? "Running" : "Stopped", isRunning: model.isRunning)
                }

                VStack(spacing: 12) {
                    InspectorInfoRow(label: "Status") {
                        Text(model.isRunning ? "Running" : "Stopped")
                    }
                    InspectorInfoRow(label: "Resolution") {
                        Text(WallpaperMetadata.resolution(for: item))
                    }
                    InspectorInfoRow(label: "Duration") {
                        Text(WallpaperMetadata.duration(for: item))
                    }
                    InspectorInfoRow(label: "File Type") {
                        Text(WallpaperMetadata.fileType(for: item))
                    }
                    InspectorInfoRow(label: "File Name") {
                        Text(WallpaperMetadata.fileName(for: item))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if item.kind == .motion {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Motion")

                        Picker("Scene", selection: model.bindingForSelectedScene()) {
                            ForEach(MotionScene.allCases) { scene in
                                Text(scene.label).tag(scene)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Picker("Palette", selection: model.bindingForSelectedPalette()) {
                            ForEach(MotionPalette.allCases) { palette in
                                Text(palette.label).tag(palette)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if let errorMessage = model.errorMessage {
                    MessageBanner(message: errorMessage, style: .error)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button(action: onStart) {
                        Label("Start Wallpaper", systemImage: "play.fill")
                    }
                    .buttonStyle(MotionDockPrimaryButtonStyle())
                    .disabled(!model.canStart)

                    HStack(spacing: 10) {
                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(MotionDockSecondaryButtonStyle())
                        .disabled(!model.isRunning)

                        Button(action: onReveal) {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .buttonStyle(MotionDockSecondaryButtonStyle())
                        .disabled(!model.canRevealSelectedItem)
                    }

                    Button(action: onFavorite) {
                        Label(isFavorite ? "Favorited" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star")
                    }
                    .buttonStyle(MotionDockSecondaryButtonStyle())

                    if model.removableSelection {
                        Button(role: .destructive, action: onRemove) {
                            Label("Remove from Library", systemImage: "trash")
                        }
                        .buttonStyle(MotionDockSecondaryButtonStyle())
                    }
                }
            } else {
                EmptyStateView(
                    icon: "rectangle.stack.badge.plus",
                    title: "No wallpapers",
                    message: "Import Wallpaper to begin."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(22)
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MotionDockTheme.secondarySurface)
    }
}

private struct WallpaperPreview: View {
    let item: WallpaperLibraryItem
    var prominent = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous)
                .fill(previewGradient)

            previewAccent
                .clipShape(RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous))

            Image(systemName: item.kind.systemImage)
                .font(.system(size: prominent ? 44 : 34, weight: .semibold))
                .foregroundStyle(Color.white.opacity(item.kind == .motion ? 0.18 : 0.34))
                .shadow(color: Color.black.opacity(0.22), radius: 12, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
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
            Button(action: onImportFiles) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Import Wallpaper")
                }
            }
            .buttonStyle(MotionDockPrimaryButtonStyle())
            .frame(width: 174)

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
            VStack(alignment: .leading, spacing: 6) {
                Text("URL import")
                    .font(.title2.weight(.semibold))
                Text("Add a web wallpaper from a direct http or https URL.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MotionDockTheme.card)
                    .frame(width: 78, height: 78)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(MotionDockTheme.accent)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: 360)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MotionDockTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: MotionDockTheme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MotionDockTheme.radius, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
    }
}

private struct PremiumPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MotionDockTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: MotionDockTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MotionDockTheme.radius, style: .continuous)
                    .stroke(MotionDockTheme.border, lineWidth: 1)
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
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(MotionDockTheme.secondaryText)
                .frame(width: 78, alignment: .leading)

            content
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            Text(message)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
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
                ProgressView()
                    .controlSize(.small)
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

private struct MotionDockTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.92))
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
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, 14)
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
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, 12)
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
        case .motion, .web:
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

    private static func localURL(for item: WallpaperLibraryItem) -> URL? {
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

private enum MotionDockTheme {
    static let background = Color(hex: 0x101113)
    static let secondarySurface = Color(hex: 0x15161A)
    static let card = Color(hex: 0x1C1D21)
    static let accent = Color(hex: 0x0A84FF)
    static let success = Color(hex: 0x30D158)
    static let border = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.56)
    static let radius: CGFloat = 18
    static let animation = Animation.easeInOut(duration: 0.18)
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
