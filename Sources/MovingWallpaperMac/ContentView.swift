import AppKit
import SwiftUI

enum MotionDockLayout {
    static let sidebarWidth: CGFloat = 240
    static let inspectorWidth: CGFloat = 320
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
    @State private var selectedSection: SidebarSection = .defaultSection
    @State private var selectedItemID: String
    @State private var observedSettingsRequestCounter: Int
    @State private var searchText = ""
    @State private var isURLImportPresented = false
    @State private var isDiscoverUploadPresented = false
    @State private var editingMyUpload: DiscoverWallpaper?
    @State private var deletingMyUpload: DiscoverWallpaper?
    @State private var discoverSearchText = ""
    @State private var discoverSortOption: DiscoverSortOption = .all
    @State private var discoverCategoryFilter: DiscoverCategoryFilter = .all
    @State private var playlistEnabled: Bool
    @State private var playlistIntervalMinutes: Double
    @State private var displayMode: DisplayMode
    @State private var performanceProfile: PerformanceProfile
    @State private var performancePolicy: PerformancePolicy
    @State private var startAtLoginEnabled: Bool
    @State private var showInDock: Bool
    @State private var isMuted: Bool
    @State private var fillMode: VideoFillMode

    init(model: AppModel) {
        self.model = model
        _selectedItemID = State(initialValue: model.selectedItemID)
        _observedSettingsRequestCounter = State(initialValue: model.settingsRequestCounter)
        _playlistEnabled = State(initialValue: model.playlistEnabled)
        _playlistIntervalMinutes = State(initialValue: model.playlistIntervalMinutes)
        _displayMode = State(initialValue: model.displayMode)
        _performanceProfile = State(initialValue: model.performanceProfile)
        _performancePolicy = State(initialValue: model.performancePolicy)
        _startAtLoginEnabled = State(initialValue: model.startAtLoginEnabled)
        _showInDock = State(initialValue: model.showInDock)
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
            let hasDetailSelection = selectedSection == .discover
                ? model.selectedDiscoverWallpaper != nil
                : model.selectedItem != nil
            let shouldShowDetail = hasDetailSelection && proxy.size.width >= minWindowWidthForDetail
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
        .onAppear {
            let resolvedSection = selectedSection.resolvedForDisplay
            if resolvedSection != selectedSection {
                selectedSection = resolvedSection
            }
        }
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
        .sheet(isPresented: $isDiscoverUploadPresented) {
            DiscoverUploadSheet(model: model)
        }
        .sheet(item: $editingMyUpload) { item in
            MyUploadEditSheet(model: model, item: item)
        }
        .alert(
            "Delete Upload?",
            isPresented: Binding(
                get: { deletingMyUpload != nil },
                set: { isPresented in
                    if !isPresented {
                        deletingMyUpload = nil
                    }
                }
            ),
            presenting: deletingMyUpload
        ) { item in
            Button("Delete", role: .destructive) {
                model.deleteMyUpload(item)
                deletingMyUpload = nil
            }
            Button("Cancel", role: .cancel) {
                deletingMyUpload = nil
            }
        } message: { item in
            Text("This removes \(item.displayTitle) from Supabase and deletes its R2 video and thumbnail files.")
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
        .onReceive(model.$showInDock) { value in
            if showInDock != value {
                showInDock = value
            }
        }
        .onReceive(model.$settingsRequestCounter) { _ in
            guard model.settingsRequestCounter != observedSettingsRequestCounter else {
                return
            }

            observedSettingsRequestCounter = model.settingsRequestCounter
            withAnimation(MotionDockTheme.animation) {
                selectedSection = .settings
            }
        }
        .onChange(of: selectedSection) { section in
            let resolvedSection = section.resolvedForDisplay
            if resolvedSection != section {
                selectedSection = resolvedSection
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
    private var inspectorPanel: some View {
        if selectedSection == .discover {
            MarketplaceDetailPanel(
                model: model,
                item: model.selectedDiscoverWallpaper
            )
        } else {
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
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedSection {
        case .library, .collections, .favorites, .recentlyAdded:
            wallpaperGridPage
                .transition(.opacity)
        case .discover:
            discoverPage
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

    private var discoverPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader(
                title: "Discover",
                subtitle: "Browse public motion wallpapers from the MotionDock marketplace.",
                showsImport: false
            )

            discoverToolbar

            discoverFilterBar

            if let message = model.discoverMessage, !model.discoverWallpapers.isEmpty {
                MessageBanner(
                    message: message,
                    style: isMarketplaceErrorMessage(message) ? .error : .neutral
                )
                .transition(.opacity)
            }

            discoverBody
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            MotionDockAmbientBackground()
        }
        .task {
            if model.discoverWallpapers.isEmpty && !model.discoverIsLoading {
                model.refreshDiscoverWallpapers()
            }
        }
        .animation(MotionDockTheme.animation, value: model.discoverIsLoading)
        .animation(MotionDockTheme.animation, value: model.discoverWallpapers.map(\.id))
        .onChange(of: discoverSearchText) { _ in
            clearDiscoverSelectionIfHidden()
        }
        .onChange(of: discoverCategoryFilter.id) { _ in
            clearDiscoverSelectionIfHidden()
        }
        .onChange(of: model.discoverWallpapers.map(\.id)) { _ in
            clearDiscoverSelectionIfHidden()
        }
    }

    private var discoverToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                discoverToolbarActions

                discoverSearchField
                    .frame(width: 280)
                    .layoutPriority(1)

                StatusPill(
                    text: discoverStatusText,
                    isRunning: !model.discoverWallpapers.isEmpty && !model.discoverIsLoading
                )

                Spacer(minLength: 8)

                discoverUserStatus
            }

            VStack(alignment: .leading, spacing: 10) {
                discoverToolbarActions

                discoverSearchField
                    .frame(maxWidth: 420)

                HStack(spacing: 10) {
                    StatusPill(
                        text: discoverStatusText,
                        isRunning: !model.discoverWallpapers.isEmpty && !model.discoverIsLoading
                    )

                    discoverUserStatus
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var discoverSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MotionDockTheme.secondaryText)
                .frame(width: 16)

            ZStack(alignment: .leading) {
                if discoverSearchText.isEmpty {
                    Text("Search wallpapers…")
                        .foregroundStyle(MotionDockTheme.secondaryText.opacity(0.78))
                        .lineLimit(1)
                }

                TextField("", text: $discoverSearchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            if !discoverSearchText.isEmpty {
                Button {
                    discoverSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(MotionDockTheme.secondaryText.opacity(0.84))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(MotionDockTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
        .clipped()
    }

    private var discoverToolbarActions: some View {
        HStack(spacing: 10) {
            Button {
                model.refreshDiscoverWallpapers()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .disabled(model.discoverIsLoading || model.discoverUploadIsLoading)

            Button {
                isDiscoverUploadPresented = true
            } label: {
                Label(
                    model.discoverUploadIsLoading ? "Uploading..." : "Upload",
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .disabled(model.discoverUploadIsLoading)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var discoverFilterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                MotionDockSegmentedPicker(
                    options: DiscoverSortOption.allCases,
                    selection: $discoverSortOption,
                    title: { $0.title }
                )
                .frame(maxWidth: 540)

                MotionDockOptionMenu(
                    options: DiscoverCategoryFilter.allCases,
                    selection: $discoverCategoryFilter,
                    title: { $0.title }
                )
                .frame(width: 190)
            }

            VStack(alignment: .leading, spacing: 10) {
                MotionDockSegmentedPicker(
                    options: DiscoverSortOption.allCases,
                    selection: $discoverSortOption,
                    title: { $0.title }
                )

                MotionDockOptionMenu(
                    options: DiscoverCategoryFilter.allCases,
                    selection: $discoverCategoryFilter,
                    title: { $0.title }
                )
                .frame(width: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var discoverUserStatus: some View {
        if let user = model.authenticatedUser {
            Text("Signed in as \(user.displayName)")
                .font(.caption.weight(.medium))
                .foregroundStyle(MotionDockTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        } else {
            Text("Browsing as guest")
                .font(.caption.weight(.medium))
                .foregroundStyle(MotionDockTheme.secondaryText)
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var discoverBody: some View {
        let visibleWallpapers = filteredDiscoverWallpapers

        if model.discoverIsLoading && model.discoverWallpapers.isEmpty {
            MarketplaceStateCard(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Loading Discover",
                message: "Fetching public wallpapers from \(model.marketplaceBackendText).",
                style: .loading
            )
            .frame(maxWidth: 520)
        } else if let message = model.discoverMessage, model.discoverWallpapers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                MarketplaceStateCard(
                    systemImage: isMarketplaceErrorMessage(message) ? "exclamationmark.triangle" : "sparkles",
                    title: isMarketplaceErrorMessage(message) ? "Discover Unavailable" : "No Wallpapers Yet",
                    message: message,
                    style: isMarketplaceErrorMessage(message) ? .error : .neutral
                )
                .frame(maxWidth: 560)

                Button {
                    model.refreshDiscoverWallpapers()
                } label: {
                    Label("Refresh Discover", systemImage: "arrow.clockwise")
                }
                .buttonStyle(MotionDockSecondaryButtonStyle())
                .disabled(model.discoverIsLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if model.discoverWallpapers.isEmpty {
            emptyState(
                icon: "sparkles.rectangle.stack",
                title: "No marketplace wallpapers",
                message: "Public wallpapers from Supabase will appear here."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleWallpapers.isEmpty {
            MarketplaceStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No matching wallpapers",
                message: "Try a different search term, category, or sort option.",
                style: .neutral
            )
            .frame(maxWidth: 560)
        } else {
            ScrollView {
                LazyVGrid(columns: discoverColumns, alignment: .leading, spacing: 18) {
                    ForEach(visibleWallpapers) { item in
                        DiscoverWallpaperCard(
                            item: item,
                            isSelected: model.selectedDiscoverWallpaper?.id == item.id,
                            isLikeBusy: model.discoverLikeIsBusy(item),
                            onSelect: {
                                withAnimation(MotionDockTheme.animation) {
                                    model.selectDiscoverWallpaper(item.id)
                                }
                            },
                            onToggleLike: {
                                model.toggleDiscoverLike(item)
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

    private var discoverStatusText: String {
        if model.discoverUploadIsLoading {
            return "Uploading"
        }
        if model.discoverIsLoading {
            return "Loading"
        }
        if model.discoverWallpapers.isEmpty {
            return "Empty"
        }
        if filteredDiscoverWallpapers.count != model.discoverWallpapers.count {
            return "\(filteredDiscoverWallpapers.count) Showing"
        }
        return "\(model.discoverWallpapers.count) Available"
    }

    private var filteredDiscoverWallpapers: [DiscoverWallpaper] {
        var items = model.discoverWallpapers

        if let category = discoverCategoryFilter.category {
            items = items.filter {
                $0.categoryText.localizedCaseInsensitiveCompare(category.rawValue) == .orderedSame
            }
        }

        let query = normalizedDiscoverSearchQuery
        if !query.isEmpty {
            items = items.filter {
                discoverSearchHaystack(for: $0).contains(query)
            }
        }

        switch discoverSortOption {
        case .all:
            return items
        case .latest:
            return items.sorted {
                let left = $0.createdAt ?? ""
                let right = $1.createdAt ?? ""
                if left == right {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return left > right
            }
        case .mostDownloaded:
            return items.sorted {
                if $0.downloads == $1.downloads {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return $0.downloads > $1.downloads
            }
        case .liked:
            return items.sorted {
                if $0.likesCount == $1.likesCount {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return $0.likesCount > $1.likesCount
            }
        }
    }

    private var normalizedDiscoverSearchQuery: String {
        discoverSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func discoverSearchHaystack(for item: DiscoverWallpaper) -> String {
        [
            item.displayTitle,
            item.descriptionText,
            item.categoryText,
            item.uploaderText
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
    }

    private func clearDiscoverSelectionIfHidden() {
        guard let selectedDiscoverWallpaperID = model.selectedDiscoverWallpaperID else {
            return
        }

        if !filteredDiscoverWallpapers.contains(where: { $0.id == selectedDiscoverWallpaperID }) {
            model.clearDiscoverSelection()
        }
    }

    private var profilesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Profiles",
                    subtitle: "Sign in to publish wallpapers and keep creator attribution synced.",
                    showsImport: false
                )

                if !model.isAuthenticated {
                    emptyState(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Sign in required",
                        message: "Use Supabase Auth to attach your account to marketplace uploads."
                    )
                    .frame(maxHeight: 220)
                }

                PremiumPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader(model.isAuthenticated ? "Account" : "Authentication")

                        InspectorInfoRow(label: "Status") {
                            StatusPill(text: model.isAuthenticated ? "Signed In" : "Signed Out", isRunning: model.isAuthenticated)
                        }

                        if let user = model.authenticatedUser {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(MotionDockTheme.accent.opacity(0.16))
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 34, weight: .semibold))
                                        .foregroundStyle(MotionDockTheme.cyan, MotionDockTheme.accent)
                                }
                                .frame(width: 58, height: 58)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.displayName)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Color.white)
                                        .lineLimit(1)
                                    Text(user.subtitle)
                                        .font(.callout)
                                        .foregroundStyle(MotionDockTheme.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            LabeledControl(title: "Display Name") {
                                HStack(spacing: 10) {
                                    MotionDockTextField("Display name", text: $model.profileDisplayNameDraft)
                                        .disabled(model.profileDisplayNameIsSaving)

                                    Button {
                                        model.saveProfileDisplayName()
                                    } label: {
                                        HStack(spacing: 6) {
                                            if model.profileDisplayNameIsSaving {
                                                MotionDockLoadingView(compact: true)
                                                    .frame(width: 34, height: 14)
                                            } else {
                                                Image(systemName: "checkmark")
                                            }

                                            Text(model.profileDisplayNameIsSaving ? "Saving" : "Save")
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .buttonStyle(MotionDockSecondaryButtonStyle())
                                    .frame(width: 104)
                                    .disabled(!model.canSaveProfileDisplayName)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            InspectorInfoRow(label: "User ID") {
                                Text(user.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(MotionDockTheme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }

                            InspectorInfoRow(label: "Email") {
                                Text(user.email ?? "Not provided")
                                    .foregroundStyle(MotionDockTheme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }

                            InspectorInfoRow(label: "Avatar URL") {
                                Text(user.avatarUrl ?? "Not provided")
                                    .foregroundStyle(MotionDockTheme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sign in with Google to publish wallpapers and keep creator attribution synced.")
                                    .font(.callout)
                                    .foregroundStyle(MotionDockTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let configurationMessage = model.authConfigurationMessage {
                                    MessageBanner(message: configurationMessage, style: .error)
                                }

                                if !model.isSupabaseConfigured {
                                    supabaseConfigurationForm
                                }
                            }
                        }

                        if let message = model.authMessage {
                            MessageBanner(
                                message: message,
                                style: message.localizedCaseInsensitiveContains("error")
                                    || message.localizedCaseInsensitiveContains("invalid")
                                    || message.localizedCaseInsensitiveContains("cancelled")
                                    ? .error
                                    : .neutral
                            )
                        }

                        HStack(spacing: 10) {
                            if model.isAuthenticated {
                                Button {
                                    model.signOutAccount()
                                } label: {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                                .buttonStyle(MotionDockSecondaryButtonStyle())

                                Button {
                                    model.useAnotherGoogleAccount()
                                } label: {
                                    Label("Use another Google account", systemImage: "person.2.badge.gearshape")
                                }
                                .buttonStyle(MotionDockSecondaryButtonStyle())
                            } else {
                                Button {
                                    model.signInWithGoogle()
                                } label: {
                                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                                }
                                .buttonStyle(MotionDockPrimaryButtonStyle())
                                .disabled(!model.isSupabaseConfigured)
                            }
                        }
                        .disabled(model.authIsLoading)
                    }
                }

                if model.isAuthenticated {
                    myUploadsSection
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
        }
        .scrollContentBackground(.hidden)
        .background {
            MotionDockAmbientBackground()
        }
        .task(id: model.authenticatedUser?.id) {
            if model.isAuthenticated && model.myUploads.isEmpty && !model.myUploadsIsLoading {
                model.refreshMyUploads()
            }
        }
    }

    private var myUploadsSection: some View {
        PremiumPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    SectionHeader("My Uploads")

                    Spacer(minLength: 12)

                    Button {
                        model.refreshMyUploads()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MotionDockSecondaryButtonStyle())
                    .frame(width: 118)
                    .disabled(model.myUploadsIsLoading)
                }

                if let message = model.myUploadsMessage {
                    MessageBanner(
                        message: message,
                        style: isMarketplaceErrorMessage(message) ? .error : .neutral
                    )
                }

                if model.myUploadsIsLoading && model.myUploads.isEmpty {
                    MarketplaceStateCard(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Loading Uploads",
                        message: "Fetching wallpapers uploaded by your account.",
                        style: .loading
                    )
                } else if model.myUploads.isEmpty {
                    MarketplaceStateCard(
                        systemImage: "square.and.arrow.up",
                        title: "No uploads yet",
                        message: "Your uploaded marketplace wallpapers will appear here.",
                        style: .neutral
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.myUploads) { item in
                            MyUploadRow(
                                item: item,
                                isBusy: model.myUploadIsBusy(item),
                                onEdit: {
                                    editingMyUpload = item
                                },
                                onDelete: {
                                    deletingMyUpload = item
                                }
                            )
                        }
                    }
                }
            }
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

                accountSettings

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

    private var accountSettings: some View {
        PremiumPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader("MotionDock 계정")

                InspectorInfoRow(label: "Status") {
                    StatusPill(text: model.isAuthenticated ? "Signed In" : "Signed Out", isRunning: model.isAuthenticated)
                }

                if let user = model.authenticatedUser {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(MotionDockTheme.accent.opacity(0.16))
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(MotionDockTheme.cyan, MotionDockTheme.accent)
                        }
                        .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(user.subtitle)
                                .font(.callout)
                                .foregroundStyle(MotionDockTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    InspectorInfoRow(label: "Email") {
                        Text(user.email ?? "Not provided")
                            .foregroundStyle(MotionDockTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    InspectorInfoRow(label: "User ID") {
                        Text(user.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(MotionDockTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Button {
                        model.signOutAccount()
                    } label: {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(MotionDockSecondaryButtonStyle())
                    .disabled(model.authIsLoading)
                } else {
                    Text("마켓플레이스 업로드에는 로그인이 필요합니다.")
                        .font(.callout)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let configurationMessage = model.authConfigurationMessage {
                        MessageBanner(message: configurationMessage, style: .error)
                    }

                    supabaseConfigurationForm

                    Button {
                        model.signInWithGoogle()
                    } label: {
                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(MotionDockPrimaryButtonStyle())
                    .disabled(model.authIsLoading || !model.isSupabaseConfigured)
                }

                if let message = model.authMessage {
                    MessageBanner(
                        message: message,
                        style: message.localizedCaseInsensitiveContains("error")
                            || message.localizedCaseInsensitiveContains("invalid")
                            || message.localizedCaseInsensitiveContains("cancelled")
                            ? .error
                            : .neutral
                    )
                }
            }
        }
    }

    private var supabaseConfigurationForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            MessageBanner(
                message: model.isSupabaseConfigured
                    ? "Supabase settings are saved. Update them here if your project URL or anon key changed."
                    : "Supabase project URL and anon key are required before Google sign-in can start.",
                style: .neutral
            )

            LabeledControl(title: "Supabase URL") {
                MotionDockTextField("https://YOUR_PROJECT_REF.supabase.co", text: $model.supabaseURLDraft)
                    .frame(maxWidth: 520)
            }

            LabeledControl(title: "Anon Key") {
                MotionDockSecureTextField("Supabase anon key", text: $model.supabaseAnonKeyDraft)
                    .frame(maxWidth: 520)
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    model.saveSupabaseConfiguration()
                } label: {
                    Label("Save Supabase Settings", systemImage: "checkmark.shield")
                }
                .buttonStyle(MotionDockSecondaryButtonStyle())
                .disabled(!model.canSaveSupabaseConfiguration)

                Text(model.supabaseConfigurationPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = model.supabaseConfigurationMessage {
                MessageBanner(
                    message: message,
                    style: message.localizedCaseInsensitiveContains("saved") ? .neutral : .error
                )
            }
        }
    }

    private var systemSettings: some View {
        PremiumPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader("System")

                LabeledControl(title: "Dock") {
                    Toggle("Show in Dock", isOn: $showInDock)
                        .toggleStyle(.switch)
                        .onChange(of: showInDock) { newValue in
                            model.setShowInDock(newValue)
                        }
                }

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
                SectionHeader("Marketplace")

                InspectorInfoRow(label: "Backend") {
                    Text(model.marketplaceBackendText)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                InspectorInfoRow(label: "Status") {
                    StatusPill(text: marketplaceStatusText, isRunning: marketplaceStatusIsRunning)
                }

                if model.authConfigurationMessage != nil {
                    LabeledControl(title: "Fallback Server") {
                        MotionDockTextField("http://127.0.0.1:8787", text: $model.marketplaceServerURLString)
                            .frame(maxWidth: 420)
                    }
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
                    .disabled(!model.canUploadSelectedItem || !model.isAuthenticated || model.marketplaceIsLoading)
                }

                if !model.isAuthenticated {
                    MessageBanner(message: "Sign in from Profiles before uploading wallpapers.", style: .neutral)
                }

                if let message = model.marketplaceMessage, shouldShowMarketplaceBanner(message) {
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
                } else {
                    marketplaceStateCard
                }
            }
        }
    }

    private var marketplaceStatusText: String {
        if model.marketplaceIsLoading {
            return "Loading"
        }
        if isMarketplaceErrorMessage(model.marketplaceMessage) {
            return "Needs Attention"
        }
        if model.marketplaceItems.isEmpty {
            return "Empty"
        }
        return "\(model.marketplaceItems.count) Available"
    }

    private var marketplaceStatusIsRunning: Bool {
        !model.marketplaceIsLoading
            && !model.marketplaceItems.isEmpty
            && !isMarketplaceErrorMessage(model.marketplaceMessage)
    }

    @ViewBuilder
    private var marketplaceStateCard: some View {
        if model.marketplaceIsLoading {
            MarketplaceStateCard(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Loading Marketplace",
                message: "Fetching the latest wallpapers from \(model.marketplaceBackendText).",
                style: .loading
            )
        } else if let message = model.marketplaceMessage, isMarketplaceErrorMessage(message) {
            MarketplaceStateCard(
                systemImage: "exclamationmark.triangle",
                title: "Marketplace Unavailable",
                message: message,
                style: .error
            )
        } else {
            MarketplaceStateCard(
                systemImage: "sparkles",
                title: "No Wallpapers Yet",
                message: marketplaceEmptyMessage,
                style: .neutral
            )
        }
    }

    private var marketplaceEmptyMessage: String {
        if model.authConfigurationMessage != nil {
            return "Configure Supabase or start the local marketplace server, then refresh."
        }
        return "Refresh after creators publish wallpapers, or upload a selected local MP4, MOV, or GIF."
    }

    private func shouldShowMarketplaceBanner(_ message: String) -> Bool {
        isMarketplaceErrorMessage(message) && !model.marketplaceItems.isEmpty
    }

    private func isMarketplaceErrorMessage(_ message: String?) -> Bool {
        guard let message else {
            return false
        }
        return message.localizedCaseInsensitiveContains("error")
            || message.localizedCaseInsensitiveContains("invalid")
            || message.localizedCaseInsensitiveContains("failed")
            || message.localizedCaseInsensitiveContains("missing")
            || message.localizedCaseInsensitiveContains("could not")
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

    private var discoverColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 18)
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

private enum DiscoverSortOption: String, CaseIterable, Identifiable {
    case all
    case latest
    case mostDownloaded
    case liked

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .latest:
            return "Latest"
        case .mostDownloaded:
            return "Most Downloaded"
        case .liked:
            return "Liked"
        }
    }
}

private struct DiscoverCategoryFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let category: MarketplaceCategory?

    static let all = DiscoverCategoryFilter(id: "all", title: "All Categories", category: nil)

    static let allCases: [DiscoverCategoryFilter] = [
        .all
    ] + MarketplaceCategory.allCases.map {
        DiscoverCategoryFilter(id: $0.id, title: $0.rawValue, category: $0)
    }
}

private enum SidebarSection: String, CaseIterable, Identifiable {
    static let defaultSection: SidebarSection = .library

    case library
    case collections
    case favorites
    case recentlyAdded
    case discover
    case profiles
    case settings

    var id: String { rawValue }

    var resolvedForDisplay: SidebarSection {
        switch self {
        case .collections:
            return Self.defaultSection
        default:
            return self
        }
    }

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
            return "Browse public marketplace wallpapers."
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
                            MetadataBadge(WallpaperMetadata.resolution(for: item))
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

private struct DiscoverWallpaperCard: View {
    let item: DiscoverWallpaper
    let isSelected: Bool
    let isLikeBusy: Bool
    let onSelect: () -> Void
    let onToggleLike: () -> Void

    @State private var isHovered = false

    var body: some View {
        MotionDockCard(isSelected: isSelected, isInteractive: isHovered) {
            VStack(alignment: .leading, spacing: 12) {
                MarketplacePreviewImage(item: item)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        MetadataBadge(item.categoryText.uppercased())
                        .padding(12)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("by \(item.uploaderText) · \(item.createdAtText)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        MarketplaceLikeButton(
                            isLiked: item.isLiked,
                            likesCount: item.likesCount,
                            isBusy: isLikeBusy,
                            action: onToggleLike
                        )
                        MarketplaceMetric(systemImage: "arrow.down.circle.fill", value: item.downloads)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .clipped()
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct MarketplaceMetric: View {
    let systemImage: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 12)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(MotionDockTheme.secondaryText)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct MarketplaceLikeButton: View {
    let isLiked: Bool
    let likesCount: Int
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.caption2.weight(.bold))
                    .frame(width: 12)
                Text("\(likesCount)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isLiked ? MotionDockTheme.cyan : MotionDockTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isLiked ? MotionDockTheme.accent.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isLiked ? MotionDockTheme.cyan.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.58 : 1)
        .fixedSize(horizontal: true, vertical: false)
        .help(isLiked ? "Unlike" : "Like")
    }
}

private struct MarketplacePreviewImage: View {
    let item: DiscoverWallpaper
    var prominent = false

    var body: some View {
        ZStack {
            marketplacePlaceholder

            if let thumbnailURL = item.thumbnailURLValue {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity.combined(with: .scale(scale: 1.01)))
                    case .failure:
                        marketplacePlaceholder
                    case .empty:
                        marketplacePlaceholder
                            .overlay {
                                MotionDockLoadingView(compact: true)
                                    .frame(width: 70, height: 28)
                            }
                    @unknown default:
                        marketplacePlaceholder
                    }
                }
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.black.opacity(prominent ? 0.16 : 0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: prominent ? MotionDockTheme.radius : 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .clipped()
    }

    private var marketplacePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MotionDockTheme.card,
                    MotionDockTheme.accent.opacity(0.26),
                    MotionDockTheme.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LiquidReflectionView(lineCount: 6, amplitude: prominent ? 8 : 5, intensity: 0.44, animated: true)
                .frame(height: prominent ? 90 : 58)
                .opacity(0.78)

            Image(systemName: "sparkles")
                .font(.system(size: prominent ? 42 : 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.20))
        }
    }
}

private struct MarketplaceDetailPanel: View {
    @ObservedObject var model: AppModel
    let item: DiscoverWallpaper?

    @State private var reportingItem: DiscoverWallpaper?

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

                    detailActions(for: item)
                }
                .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            } else {
                EmptyStateView(
                    icon: "sparkles.rectangle.stack",
                    title: "No marketplace item",
                    message: "Select a Discover wallpaper to view details."
                )
                .frame(width: MotionDockLayout.inspectorContentWidth)
                .frame(maxHeight: .infinity)
                .clipped()
            }
        }
        .padding(.horizontal, MotionDockLayout.inspectorHorizontalPadding)
        .padding(.vertical, MotionDockLayout.inspectorVerticalPadding)
        .frame(width: MotionDockLayout.inspectorWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MotionDockTheme.secondarySurface)
        .clipped()
        .sheet(item: $reportingItem) { item in
            ReportWallpaperSheet(model: model, item: item)
        }
    }

    private func detailContent(for item: DiscoverWallpaper) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            MarketplacePreviewImage(item: item, prominent: true)
                .frame(
                    width: MotionDockLayout.inspectorContentWidth,
                    height: MotionDockLayout.inspectorContentWidth * 11.0 / 16.0
                )
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(item.displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                    .clipped()

                StatusPill(
                    text: model.discoverBusyItemID == item.id
                        ? "Adding to Library"
                        : discoverActionStatusText(for: item),
                    isRunning: item.hasDownloadableVideo
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
            .clipped()

            VStack(spacing: 12) {
                DetailInfoRow(label: "Category", value: item.categoryText)
                DetailInfoRow(label: "Likes", value: "\(item.likesCount)")
                DetailInfoRow(label: "Downloads", value: "\(item.downloads)")
                DetailInfoRow(label: "Uploader", value: item.uploaderText, truncationMode: .middle)
                DetailInfoRow(label: "Added", value: item.createdAtText, truncationMode: .middle)
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Description")
                Text(item.descriptionText)
                    .font(.callout)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                    .clipped()
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
            .clipped()

            if let message = model.discoverMessage {
                MessageBanner(
                    message: message,
                    style: message.localizedCaseInsensitiveContains("error")
                        || message.localizedCaseInsensitiveContains("invalid")
                        || message.localizedCaseInsensitiveContains("failed")
                        || message.localizedCaseInsensitiveContains("could not")
                        ? .error
                        : .neutral
                )
                .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
                .clipped()
            }
        }
        .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .topLeading)
        .clipped()
    }

    private func detailActions(for item: DiscoverWallpaper) -> some View {
        let isBusy = model.discoverBusyItemID == item.id
        let isLikeBusy = model.discoverLikeIsBusy(item)
        let isReportBusy = model.discoverReportIsBusy(item)
        let isInLibrary = model.discoverWallpaperIsInLibrary(item)

        return VStack(spacing: 10) {
            DetailActionButton(
                title: item.isLiked ? "Liked" : "Like",
                systemImage: item.isLiked ? "heart.fill" : "heart",
                style: .secondary,
                isDisabled: isLikeBusy,
                action: {
                    model.toggleDiscoverLike(item)
                }
            )

            if item.hasDownloadableVideo {
                if isBusy {
                    MotionDockLoadingView(compact: true)
                        .frame(width: 74, height: 20)
                        .padding(.bottom, 2)
                }

                DetailActionButton(
                    title: isBusy ? "Adding to Library..." : (isInLibrary ? "Already in Library" : "Add to Library"),
                    systemImage: "plus",
                    style: .primary,
                    isDisabled: isBusy,
                    action: {
                        model.requestAddDiscoverWallpaperToLibrary(item)
                    }
                )
            } else {
                DetailActionButton(
                    title: "Add Unavailable",
                    systemImage: "slash.circle",
                    style: .secondary,
                    isDisabled: true,
                    action: {}
                )
            }

            DetailActionButton(
                title: isReportBusy ? "Reporting..." : "Report",
                systemImage: "exclamationmark.bubble",
                style: .secondary,
                isDisabled: isReportBusy,
                action: {
                    reportingItem = item
                }
            )
        }
        .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .center)
        .clipped()
    }

    private func discoverActionStatusText(for item: DiscoverWallpaper) -> String {
        if model.discoverWallpaperIsInLibrary(item) {
            return "Already in Library"
        }
        return item.hasDownloadableVideo ? "Add Available" : "Preview Only"
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
                DetailInfoRow(label: "File Size", value: WallpaperMetadata.fileSize(for: item))
                DetailInfoRow(label: "Added", value: WallpaperMetadata.added(for: item))
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, alignment: .leading)
            .clipped()

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

private struct DiscoverUploadSheet: View {
    @ObservedObject var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFileURL: URL?
    @State private var title = ""
    @State private var category: MarketplaceCategory = .cinematic
    @State private var description = ""
    @State private var hasAcceptedTerms = false
    @State private var isUploadTermsPresented = false
    @State private var didStartUpload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                MotionDockLogoView(size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload Wallpaper")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)

                    Text("Publish an MP4 or MOV wallpaper to Discover.")
                        .font(.callout)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.isAuthenticated {
                MessageBanner(
                    message: "Sign in with Google before uploading marketplace wallpapers.",
                    style: .neutral
                )
            }

            if let message = model.discoverMessage {
                MessageBanner(
                    message: message,
                    style: isUploadErrorMessage(message) ? .error : .neutral
                )
            }

            PremiumPanel {
                VStack(alignment: .leading, spacing: 16) {
                    uploadFileRow

                    LabeledControl(title: "Title") {
                        MotionDockTextField("Wallpaper title", text: $title)
                    }

                    LabeledControl(title: "Category") {
                        MotionDockOptionMenu(
                            options: MarketplaceCategory.allCases,
                            selection: $category,
                            title: { $0.rawValue }
                        )
                        .frame(width: 220)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(MotionDockTheme.secondaryText)

                        TextEditor(text: $description)
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 92)
                            .background(MotionDockTheme.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MotionDockTheme.border, lineWidth: 1)
                            }
                    }

                    termsConsentRow
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(MotionDockSecondaryButtonStyle())
                .disabled(model.discoverUploadIsLoading)

                Button {
                    guard let selectedFileURL else {
                        return
                    }
                    model.uploadDiscoverMarketplaceWallpaper(
                        fileURL: selectedFileURL,
                        title: title,
                        description: description,
                        category: category,
                        confirmedRights: hasAcceptedTerms
                    )
                    didStartUpload = true
                } label: {
                    HStack(spacing: 8) {
                        if model.discoverUploadIsLoading {
                            MotionDockLoadingView(compact: true)
                                .frame(width: 44, height: 16)
                        }
                        Text(model.discoverUploadIsLoading ? "Uploading..." : "Upload")
                    }
                }
                .buttonStyle(MotionDockPrimaryButtonStyle())
                .disabled(!canUpload)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(MotionDockTheme.background)
        .sheet(isPresented: $isUploadTermsPresented) {
            MarketplaceUploadTermsSheet()
        }
        .onChange(of: model.discoverUploadIsLoading) { isLoading in
            guard didStartUpload, !isLoading else {
                return
            }

            if model.discoverMessage?.localizedCaseInsensitiveContains("complete") == true {
                hasAcceptedTerms = false
            }
            didStartUpload = false
        }
    }

    private var uploadFileRow: some View {
        LabeledControl(title: "File") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedFileURL?.lastPathComponent ?? "No file selected")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(MarketplaceUploadPolicy.supportedR2UploadTypesText)
                        .font(.caption)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    chooseUploadFile()
                } label: {
                    Label("Choose", systemImage: "folder")
                }
                .buttonStyle(MotionDockSecondaryButtonStyle())
                .frame(width: 120)
                .disabled(model.discoverUploadIsLoading)
            }
        }
    }

    private var canUpload: Bool {
        model.isAuthenticated
            && selectedFileURL != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasAcceptedTerms
            && !model.discoverUploadIsLoading
    }

    private var termsConsentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                hasAcceptedTerms.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: hasAcceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hasAcceptedTerms ? MotionDockTheme.accent : MotionDockTheme.secondaryText)
                        .frame(width: 22, alignment: .center)

                    Text(MarketplaceUploadTerms.shortConsent)
                        .font(.caption)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.discoverUploadIsLoading)

            Button {
                isUploadTermsPresented = true
            } label: {
                Label("View Terms", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseUploadFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Marketplace Wallpaper"
        panel.message = "Choose an MP4 or MOV wallpaper to upload."

        guard panel.runModal() == .OK, let url = panel.urls.first else {
            return
        }

        selectedFileURL = url
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
    }

    private func isUploadErrorMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("error")
            || lowercased.contains("invalid")
            || lowercased.contains("failed")
            || lowercased.contains("missing")
            || lowercased.contains("not configured")
            || lowercased.contains("unsupported")
    }
}

private struct MarketplaceUploadTermsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(MarketplaceUploadTerms.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)

                Text(MarketplaceUploadTerms.subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MotionDockTheme.cyan)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(MarketplaceUploadTerms.body)
                    .font(.callout)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 360)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(MotionDockPrimaryButtonStyle())
                .frame(width: 120)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .background(MotionDockTheme.background)
    }
}

private struct ReportWallpaperSheet: View {
    @ObservedObject var model: AppModel
    let item: DiscoverWallpaper

    @Environment(\.dismiss) private var dismiss
    @State private var reason: MarketplaceReportReason = .copyright
    @State private var details = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MotionDockTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(MotionDockTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Report Wallpaper")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)

                    Text(item.displayTitle)
                        .font(.callout)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.isAuthenticated {
                MessageBanner(
                    message: "Sign in with Google before reporting marketplace wallpapers.",
                    style: .neutral
                )
            }

            if let message = model.discoverMessage {
                MessageBanner(
                    message: message,
                    style: isReportErrorMessage(message) ? .error : .neutral
                )
            }

            PremiumPanel {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledControl(title: "Reason") {
                        MotionDockOptionMenu(
                            options: MarketplaceReportReason.allCases,
                            selection: $reason,
                            title: { $0.rawValue }
                        )
                        .frame(width: 220)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(MotionDockTheme.secondaryText)

                        TextEditor(text: $details)
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 110)
                            .background(MotionDockTheme.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MotionDockTheme.border, lineWidth: 1)
                            }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(MotionDockSecondaryButtonStyle())
                .disabled(model.discoverReportIsBusy(item))

                Button {
                    model.reportDiscoverWallpaper(
                        item,
                        reason: reason,
                        details: details
                    )
                    dismiss()
                } label: {
                    Text(model.discoverReportIsBusy(item) ? "Reporting..." : "Submit Report")
                }
                .buttonStyle(MotionDockPrimaryButtonStyle())
                .disabled(!model.isAuthenticated || model.discoverReportIsBusy(item))
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(MotionDockTheme.background)
    }

    private func isReportErrorMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("error")
            || lowercased.contains("invalid")
            || lowercased.contains("failed")
            || lowercased.contains("could not")
            || lowercased.contains("already reported")
    }
}

private struct MyUploadRow: View {
    let item: DiscoverWallpaper
    let isBusy: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MarketplacePreviewImage(item: item)
                .frame(width: 148, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipped()

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(item.displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    MetadataBadge(item.categoryText.uppercased())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.descriptionText)
                    .font(.caption)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    MarketplaceMetric(systemImage: "heart.fill", value: item.likesCount)
                    MarketplaceMetric(systemImage: "arrow.down.circle.fill", value: item.downloads)
                    Text(item.createdAtText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MotionDockTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            if isBusy {
                MotionDockLoadingView(compact: true)
                    .frame(width: 58, height: 20)
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .frame(width: 92)
            .disabled(isBusy)

            Button {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .frame(width: 104)
            .disabled(isBusy)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MotionDockTheme.secondarySurface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
        .clipped()
    }
}

private struct MyUploadEditSheet: View {
    @ObservedObject var model: AppModel
    let item: DiscoverWallpaper

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: MarketplaceCategory
    @State private var description: String

    init(model: AppModel, item: DiscoverWallpaper) {
        self.model = model
        self.item = item
        _title = State(initialValue: item.displayTitle)
        _category = State(initialValue: Self.initialCategory(for: item))
        _description = State(initialValue: item.description ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                MarketplacePreviewImage(item: item)
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Upload")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)

                    Text("Update marketplace metadata for this wallpaper.")
                        .font(.callout)
                        .foregroundStyle(MotionDockTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = model.myUploadsMessage {
                MessageBanner(
                    message: message,
                    style: message.localizedCaseInsensitiveContains("could not") ? .error : .neutral
                )
            }

            PremiumPanel {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledControl(title: "Title") {
                        MotionDockTextField("Wallpaper title", text: $title)
                    }

                    LabeledControl(title: "Category") {
                        MotionDockOptionMenu(
                            options: MarketplaceCategory.allCases,
                            selection: $category,
                            title: { $0.rawValue }
                        )
                        .frame(width: 220)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(MotionDockTheme.secondaryText)

                        TextEditor(text: $description)
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 104)
                            .background(MotionDockTheme.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MotionDockTheme.border, lineWidth: 1)
                            }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(MotionDockSecondaryButtonStyle())
                .disabled(model.myUploadIsBusy(item))

                Button {
                    model.updateMyUpload(
                        item,
                        title: title,
                        description: description,
                        category: category
                    )
                    dismiss()
                } label: {
                    Label("Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(MotionDockPrimaryButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.myUploadIsBusy(item))
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(MotionDockTheme.background)
    }

    private static func initialCategory(for item: DiscoverWallpaper) -> MarketplaceCategory {
        MarketplaceCategory.allCases.first {
            $0.rawValue.localizedCaseInsensitiveCompare(item.categoryText) == .orderedSame
        } ?? .other
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

private enum MarketplaceStateCardStyle {
    case neutral
    case loading
    case error
}

private struct MarketplaceStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    var style: MarketplaceStateCardStyle = .neutral

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }
            .frame(width: 42, height: 42)
            .overlay(alignment: .bottom) {
                if style == .loading {
                    MotionDockLoadingView(compact: true)
                        .frame(width: 44, height: 16)
                        .offset(y: 16)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MotionDockTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .clipped()
    }

    private var iconBackground: Color {
        switch style {
        case .neutral:
            return MotionDockTheme.accent.opacity(0.14)
        case .loading:
            return MotionDockTheme.cyan.opacity(0.14)
        case .error:
            return Color.red.opacity(0.14)
        }
    }

    private var iconForeground: Color {
        switch style {
        case .neutral:
            return MotionDockTheme.accent
        case .loading:
            return MotionDockTheme.cyan
        case .error:
            return Color.red.opacity(0.92)
        }
    }

    private var borderColor: Color {
        switch style {
        case .neutral:
            return MotionDockTheme.border
        case .loading:
            return MotionDockTheme.cyan.opacity(0.16)
        case .error:
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
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    if item.moderationStatusValue != .approved {
                        StatusPill(
                            text: item.moderationStatusValue.displayText,
                            isRunning: false
                        )
                    }
                }
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
                .disabled(isBusy || item.supportedKind == nil || !item.moderationStatusValue.allowsDownload)

            Button("Apply", action: onApply)
                .buttonStyle(.borderless)
                .disabled(isBusy || item.supportedKind == nil || !item.moderationStatusValue.allowsDownload)
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

private struct MotionDockSecureTextField: View {
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

            SecureField("", text: $text)
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
