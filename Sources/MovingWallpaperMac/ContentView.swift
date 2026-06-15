import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var activeTab: MainTab = .library
    @State private var selectedItemID: String
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
        VStack(spacing: 0) {
            tabHeader

            Divider()

            tabContent
        }
        .frame(minWidth: 1040, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
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

    private var tabHeader: some View {
        HStack(spacing: 16) {
            Label("Moving Wallpaper", systemImage: "rectangle.stack")
                .font(.headline)

            Picker("탭", selection: $activeTab) {
                ForEach(MainTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 560)
            .onChange(of: activeTab) { newValue in
                if newValue == .marketplace {
                    model.refreshMarketplace()
                }
            }

            Spacer()

            Text(model.statusText)
                .font(.callout.weight(.medium))
                .foregroundStyle(model.isRunning ? (model.isSuspended ? .orange : .green) : .secondary)

            Button {
                model.stop()
            } label: {
                Label("정지", systemImage: "stop.fill")
            }
            .disabled(!model.isRunning)

            Button {
                model.start()
            } label: {
                Label("시작", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canStart)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .library:
            HStack(spacing: 0) {
                libraryPane

                Divider()

                libraryDetailPane
            }
        case .marketplace:
            marketplaceTab
        case .profile:
            profileTab
        case .settings:
            settingsTab
        }
    }

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Library", systemImage: "rectangle.stack")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            List(selection: $selectedItemID) {
                ForEach(model.libraryItems) { item in
                    LibraryRow(item: item)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedItemID) { newValue in
                model.selectItem(newValue)
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        model.addMediaFiles()
                    } label: {
                        Label("Media", systemImage: "photo.stack")
                    }

                    Button {
                        model.removeSelectedItem()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("선택한 항목 삭제")
                    .disabled(!model.removableSelection)
                }

                HStack(spacing: 8) {
                    TextField("https://example.com", text: $model.webURLDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        model.addWebsite()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("웹 배경 추가")
                }
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            if let item = model.selectedItem {
                selectedItemControls(for: item)
            }

            playbackControls

            performanceControls

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            runControls
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var libraryDetailPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            if let item = model.selectedItem {
                selectedItemControls(for: item)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            runControls
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var marketplacePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Marketplace", systemImage: "square.and.arrow.down")
                    .font(.headline)
                Spacer()
            }

            TextField("http://127.0.0.1:8787", text: $model.marketplaceServerURLString)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    model.refreshMarketplace()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .disabled(model.marketplaceIsLoading)

                Button {
                    model.uploadSelectedItemToMarketplace()
                } label: {
                    Label("업로드", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.canUploadSelectedItem || model.marketplaceIsLoading)
            }

            if let message = model.marketplaceMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(message.contains("오류") || message.contains("없습니다") || message.contains("올바르지") ? .red : .secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if model.marketplaceItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("업로드된 배경이 없습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.marketplaceItems) { item in
                            MarketplaceRow(
                                item: item,
                                isBusy: model.marketplaceBusyItemID == item.id,
                                onDownload: {
                                    model.downloadMarketplaceItem(item, apply: false)
                                },
                                onApply: {
                                    model.downloadMarketplaceItem(item, apply: true)
                                }
                            )

                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 330, idealWidth: 350, maxWidth: 420)
    }

    private var marketplaceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("Marketplace", systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.semibold))

                TextField("http://127.0.0.1:8787", text: $model.marketplaceServerURLString)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Button {
                    model.refreshMarketplace()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .disabled(model.marketplaceIsLoading)

                Button {
                    model.uploadSelectedItemToMarketplace()
                } label: {
                    Label("업로드", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.canUploadSelectedItem || !model.profileIsLoggedIn || model.marketplaceIsLoading)

                Spacer()
            }

            if let message = model.marketplaceMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(message.contains("오류") || message.contains("없습니다") || message.contains("올바르지") ? .red : .secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if model.marketplaceItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("업로드된 배경이 없습니다.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.marketplaceItems) { item in
                            MarketplaceRow(
                                item: item,
                                isBusy: model.marketplaceBusyItemID == item.id,
                                onDownload: {
                                    model.downloadMarketplaceItem(item, apply: false)
                                    activeTab = .library
                                },
                                onApply: {
                                    model.downloadMarketplaceItem(item, apply: true)
                                    activeTab = .library
                                }
                            )

                            Divider()
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Label("Settings", systemImage: "gearshape")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            Divider()

            playbackControls

            performanceControls

            Spacer()

            runControls
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var profileTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Label("Profile", systemImage: "person.crop.circle")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Account")

                SettingRow(title: "상태") {
                    Label(
                        model.profileIsLoggedIn ? "로그인됨" : "로그아웃",
                        systemImage: model.profileIsLoggedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.xmark"
                    )
                    .foregroundStyle(model.profileIsLoggedIn ? Color.green : Color.secondary)
                }

                SettingRow(title: "이름") {
                    TextField("표시 이름", text: $model.profileDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                SettingRow(title: "핸들") {
                    HStack(spacing: 6) {
                        Text("@")
                            .foregroundStyle(.secondary)
                        TextField("handle", text: $model.profileHandle)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                }

                SettingRow(title: "작성자") {
                    Text(model.profileDisplayText)
                        .foregroundStyle(model.profileIsLoggedIn ? Color.primary : Color.secondary)
                        .lineLimit(1)
                }

                SettingRow(title: "ID") {
                    Text(model.profileID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            if let message = model.profileMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(message.contains("입력") ? .red : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    model.signInProfile()
                } label: {
                    Label(model.profileIsLoggedIn ? "다시 로그인" : "로그인", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.signOutProfile()
                } label: {
                    Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(!model.profileIsLoggedIn)
            }

            Spacer()

            runControls
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: model.selectedItem?.kind.systemImage ?? "desktopcomputer")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedItem?.name ?? "Moving Wallpaper")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.isRunning ? (model.isSuspended ? .orange : .green) : .secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func selectedItemControls(for item: WallpaperLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Wallpaper")

            SettingRow(title: "종류") {
                Label(item.kind.label, systemImage: item.kind.systemImage)
                    .foregroundStyle(.secondary)
            }

            SettingRow(title: "정보") {
                Text(item.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if item.kind == .motion {
                SettingRow(title: "프리셋") {
                    Picker("프리셋", selection: model.bindingForSelectedScene()) {
                        ForEach(MotionScene.allCases) { scene in
                            Text(scene.label).tag(scene)
                        }
                    }
                    .frame(width: 180)
                }

                SettingRow(title: "팔레트") {
                    Picker("팔레트", selection: model.bindingForSelectedPalette()) {
                        ForEach(MotionPalette.allCases) { palette in
                            Text(palette.label).tag(palette)
                        }
                    }
                    .frame(width: 180)
                }
            }
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Playback")

            SettingRow(title: "모니터") {
                Picker("모니터", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .onChange(of: displayMode) { newValue in
                    model.setDisplayMode(newValue)
                }
            }

            SettingRow(title: "재생") {
                HStack(spacing: 14) {
                    Toggle("음소거", isOn: $isMuted)
                        .onChange(of: isMuted) { newValue in
                            model.setMuted(newValue)
                        }

                    Picker("비율", selection: $fillMode) {
                        ForEach(VideoFillMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .frame(width: 120)
                    .onChange(of: fillMode) { newValue in
                        model.setFillMode(newValue)
                    }
                }
            }

            SettingRow(title: "목록") {
                HStack(spacing: 12) {
                    Toggle("순환", isOn: $playlistEnabled)
                        .onChange(of: playlistEnabled) { newValue in
                            model.setPlaylistEnabled(newValue)
                        }

                    Stepper(
                        "\(Int(playlistIntervalMinutes))분",
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

    private var performanceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Performance")

            SettingRow(title: "프로필") {
                Picker("프로필", selection: $performanceProfile) {
                    ForEach(PerformanceProfile.allCases) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .onChange(of: performanceProfile) { newValue in
                    model.setPerformanceProfile(newValue)
                }
            }

            SettingRow(title: "정책") {
                Picker("정책", selection: $performancePolicy) {
                    ForEach(PerformancePolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .frame(width: 210)
                .onChange(of: performancePolicy) { newValue in
                    model.setPerformancePolicy(newValue)
                }
            }
        }
    }

    private var runControls: some View {
        HStack {
            Button {
                model.advancePlaylist()
            } label: {
                Label("다음", systemImage: "forward.fill")
            }
            .disabled(!model.isRunning || model.libraryItems.count < 2)

            Spacer()

            Button {
                model.stop()
            } label: {
                Label("정지", systemImage: "stop.fill")
            }
            .disabled(!model.isRunning)

            Button {
                model.start()
            } label: {
                Label("시작", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canStart)
        }
        .controlSize(.large)
    }
}

private struct LibraryRow: View {
    let item: WallpaperLibraryItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private enum MainTab: String, CaseIterable, Identifiable {
    case library
    case marketplace
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            "라이브러리"
        case .marketplace:
            "마켓플레이스"
        case .profile:
            "프로필"
        case .settings:
            "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "rectangle.stack"
        case .marketplace:
            "square.and.arrow.down"
        case .profile:
            "person.crop.circle"
        case .settings:
            "gearshape"
        }
    }
}

private struct MarketplaceRow: View {
    let item: MarketplaceItem
    let isBusy: Bool
    let onDownload: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.supportedKind?.systemImage ?? "questionmark.square")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Label("올린 사람 \(item.uploaderDisplayText)", systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onDownload()
                } label: {
                    Label("받기", systemImage: "arrow.down.circle")
                }
                .disabled(isBusy || item.supportedKind == nil)

                Button {
                    onApply()
                } label: {
                    Label("받고 적용", systemImage: "play.circle")
                }
                .disabled(isBusy || item.supportedKind == nil)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 12)
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.headline)
                .frame(width: 72, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
