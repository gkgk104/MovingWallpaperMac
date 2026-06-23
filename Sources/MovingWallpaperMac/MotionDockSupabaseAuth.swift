import AppKit
import Foundation
import Supabase
import UniformTypeIdentifiers

struct MotionDockAuthenticatedUser: Equatable {
    var id: String
    var displayName: String
    var email: String?
    var avatarUrl: String?

    var subtitle: String {
        if let email, !email.isEmpty {
            return email
        }
        return id
    }
}

struct MotionDockSupabaseConfiguration {
    let url: URL
    let anonKey: String
    let marketplaceBucket: String
    let marketplaceTable: String

    static let applicationSupportRelativePath = "MotionDock/Supabase.plist"
    static let defaultMarketplaceBucket = "wallpapers"
    static let defaultMarketplaceTable = "wallpapers"

    static func load() throws -> MotionDockSupabaseConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if
            let rawURL = environment["MOTIONDOCK_SUPABASE_URL"]?.trimmedNonEmpty,
            let anonKey = environment["MOTIONDOCK_SUPABASE_ANON_KEY"]?.trimmedNonEmpty,
            let url = URL(string: rawURL)
        {
            return MotionDockSupabaseConfiguration(
                url: url,
                anonKey: anonKey,
                marketplaceBucket: environment["MOTIONDOCK_SUPABASE_MARKETPLACE_BUCKET"]?.trimmedNonEmpty ?? defaultMarketplaceBucket,
                marketplaceTable: environment["MOTIONDOCK_SUPABASE_MARKETPLACE_TABLE"]?.trimmedNonEmpty ?? defaultMarketplaceTable
            )
        }

        if let config = try loadPlist(from: applicationSupportConfigURL) {
            return config
        }

        if let bundledURL = Bundle.module.url(forResource: "Supabase", withExtension: "plist"),
           let config = try loadPlist(from: bundledURL) {
            return config
        }

        throw MotionDockAuthError.missingSupabaseConfiguration
    }

    static var applicationSupportConfigURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent(applicationSupportRelativePath)
    }

    static func save(
        url: URL,
        anonKey: String,
        marketplaceBucket: String = defaultMarketplaceBucket,
        marketplaceTable: String = defaultMarketplaceTable
    ) throws {
        let configURL = applicationSupportConfigURL
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: String] = [
            "supabaseURL": url.absoluteString,
            "anonKey": anonKey,
            "marketplaceBucket": marketplaceBucket.trimmedNonEmpty ?? defaultMarketplaceBucket,
            "marketplaceTable": marketplaceTable.trimmedNonEmpty ?? defaultMarketplaceTable
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: configURL, options: .atomic)
    }

    private static func loadPlist(from url: URL) throws -> MotionDockSupabaseConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw MotionDockAuthError.invalidSupabaseConfiguration
        }

        let rawURL = (plist["supabaseURL"] as? String)?.trimmedNonEmpty
            ?? (plist["url"] as? String)?.trimmedNonEmpty
        let anonKey = (plist["anonKey"] as? String)?.trimmedNonEmpty
            ?? (plist["supabaseAnonKey"] as? String)?.trimmedNonEmpty
        let marketplaceBucket = (plist["marketplaceBucket"] as? String)?.trimmedNonEmpty ?? defaultMarketplaceBucket
        let marketplaceTable = (plist["marketplaceTable"] as? String)?.trimmedNonEmpty ?? defaultMarketplaceTable

        guard let rawURL, let anonKey, let url = URL(string: rawURL) else {
            throw MotionDockAuthError.invalidSupabaseConfiguration
        }
        return MotionDockSupabaseConfiguration(
            url: url,
            anonKey: anonKey,
            marketplaceBucket: marketplaceBucket,
            marketplaceTable: marketplaceTable
        )
    }
}

enum MotionDockAuthError: LocalizedError {
    case missingSupabaseConfiguration
    case invalidSupabaseConfiguration
    case invalidOAuthCallback(String)
    case invalidResponse(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingSupabaseConfiguration:
            return "Supabase is not configured. Set MOTIONDOCK_SUPABASE_URL and MOTIONDOCK_SUPABASE_ANON_KEY, or create ~/Library/Application Support/MotionDock/Supabase.plist."
        case .invalidSupabaseConfiguration:
            return "Supabase configuration is invalid."
        case .invalidOAuthCallback(let message):
            return message
        case .invalidResponse(let message):
            return message
        case .cancelled:
            return "Google sign-in was cancelled."
        }
    }
}

@MainActor
private final class MotionDockOAuthCallbackCoordinator {
    static let shared = MotionDockOAuthCallbackCoordinator()

    private var continuation: CheckedContinuation<URL, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    private init() {}

    func openAndWaitForCallback(_ authorizationURL: URL) async throws -> URL {
        cancelPendingCallback()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let timeout = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.cancelPendingCallback()
                }
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)

            let components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
            let queryKeys = components?.queryItems?.map(\.name).joined(separator: ",") ?? ""
            NSLog(
                "[MotionDock OAuth] opening authorization URL host=%@ path=%@ queryKeys=%@",
                authorizationURL.host ?? "",
                authorizationURL.path,
                queryKeys
            )
            NSWorkspace.shared.open(authorizationURL)
        }
    }

    func complete(with callbackURL: URL) -> Bool {
        guard let continuation else {
            return false
        }

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.continuation = nil
        continuation.resume(returning: callbackURL)
        return true
    }

    func fail(with error: Error) -> Bool {
        guard let continuation else {
            return false
        }

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.continuation = nil
        continuation.resume(throwing: error)
        return true
    }

    private func cancelPendingCallback() {
        guard let continuation else {
            return
        }

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.continuation = nil
        continuation.resume(throwing: MotionDockAuthError.cancelled)
    }
}

@MainActor
final class MotionDockSupabaseAuthService {
    private static let oauthRedirectScheme = "motiondock"
    private static let oauthRedirectHost = "auth-callback"
    private static let discoverBaseSelect = "id,title,description,uploader_id,thumbnail_url,video_url,category,downloads,likes_count,uploader_confirmed_rights,report_count,is_hidden,created_at"
    private static let discoverSelectWithProfileHandle = "\(discoverBaseSelect),profiles(display_name,handle,email)"
    private static let discoverSelectWithProfile = "\(discoverBaseSelect),profiles(display_name,email)"
    private static let wallpaperLikesTable = "wallpaper_likes"
    private static let reportWallpaperRPCName = "report_wallpaper"
    private static let reportWallpaperRPCParameterKeys = ["p_wallpaper_id", "p_reason", "p_details"]

    static var reportWallpaperRPCDescription: String {
        "\(reportWallpaperRPCName)(\(reportWallpaperRPCParameterKeys.joined(separator: ", ")))"
    }

    private static var oauthRedirectURL: URL {
        var components = URLComponents()
        components.scheme = oauthRedirectScheme
        components.host = oauthRedirectHost
        return components.url ?? URL(fileURLWithPath: "/")
    }

    private let client: SupabaseClient?
    private let configuration: MotionDockSupabaseConfiguration?
    private let configurationError: Error?

    init() {
        do {
            let configuration = try MotionDockSupabaseConfiguration.load()
            self.configuration = configuration
            client = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.anonKey,
                options: SupabaseClientOptions(
                    auth: .init(redirectToURL: Self.oauthRedirectURL)
                )
            )
            configurationError = nil
        } catch {
            self.configuration = nil
            client = nil
            configurationError = error
        }
    }

    var isConfigured: Bool {
        client != nil
    }

    var configurationMessage: String? {
        configurationError?.localizedDescription
    }

    var marketplaceDescription: String {
        guard let configuration else {
            return "Local server fallback"
        }
        return "Supabase · \(configuration.marketplaceTable)"
    }

    static func isOAuthCallbackURL(_ url: URL) -> Bool {
        url.scheme?.localizedCaseInsensitiveCompare(oauthRedirectScheme) == .orderedSame
            && url.host?.localizedCaseInsensitiveCompare(oauthRedirectHost) == .orderedSame
    }

    static func authorizationCode(in callbackURL: URL) -> String? {
        URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "code" }?
            .value?
            .trimmedNonEmpty
    }

    static func callbackErrorMessage(in callbackURL: URL) -> String? {
        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let errorDescription = queryItems.first { $0.name == "error_description" }?.value
        let error = queryItems.first { $0.name == "error" }?.value
        return (errorDescription ?? error)?.replacingOccurrences(of: "+", with: " ")
    }

    func restoreSession() async throws -> MotionDockAuthenticatedUser? {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        guard client.auth.currentSession != nil else {
            return nil
        }

        let session = try await client.auth.session
        return try await syncProfile(for: session.user, preferredProfile: nil)
    }

    func signInWithGoogle(forceAccountSelection: Bool = true) async throws -> MotionDockAuthenticatedUser {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        do {
            let queryParams = Self.googleOAuthQueryParams(forceAccountSelection: forceAccountSelection)
            NSLog(
                "[MotionDock OAuth] starting Google OAuth with redirectTo=%@ queryParams=%@",
                Self.oauthRedirectURL.absoluteString,
                queryParams.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            )
            let session = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: Self.oauthRedirectURL,
                queryParams: queryParams
            ) { authorizationURL in
                try await MotionDockOAuthCallbackCoordinator.shared.openAndWaitForCallback(authorizationURL)
            }
            NSLog("[MotionDock OAuth] session exchange success for user=%@", session.user.id.uuidString)
            return try await syncProfile(for: session.user, preferredProfile: nil)
        } catch {
            NSLog("[MotionDock OAuth] session exchange failure: %@", error.localizedDescription)
            throw error
        }
    }

    private static func googleOAuthQueryParams(forceAccountSelection: Bool) -> [(name: String, value: String?)] {
        guard forceAccountSelection else {
            return []
        }

        return [
            (name: "prompt", value: "select_account")
        ]
    }

    func completePendingOAuthCallback(_ url: URL) -> Bool {
        guard Self.isOAuthCallbackURL(url) else {
            return false
        }

        return MotionDockOAuthCallbackCoordinator.shared.complete(with: url)
    }

    func failPendingOAuthCallback(with error: Error) -> Bool {
        MotionDockOAuthCallbackCoordinator.shared.fail(with: error)
    }

    func completeOAuthCallback(_ url: URL) async throws -> MotionDockAuthenticatedUser {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }
        guard Self.isOAuthCallbackURL(url) else {
            throw MotionDockAuthError.cancelled
        }
        guard Self.authorizationCode(in: url) != nil else {
            throw MotionDockAuthError.invalidOAuthCallback("Google sign-in callback did not include an authorization code.")
        }

        do {
            NSLog("[MotionDock OAuth] exchanging callback URL through Supabase session(from:)")
            let session = try await client.auth.session(from: url)
            NSLog("[MotionDock OAuth] session exchange success for user=%@", session.user.id.uuidString)
            return try await syncProfile(for: session.user, preferredProfile: nil)
        } catch {
            NSLog("[MotionDock OAuth] session exchange failure: %@", error.localizedDescription)
            throw error
        }
    }

    func signOut() async throws {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }
        try await client.auth.signOut()
    }

    func listMarketplaceWallpapers() async throws -> [MarketplaceItem] {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseWallpaperRow]> = try await client
            .from(configuration.marketplaceTable)
            .select("id,title,kind,filename,file_size,created_at,storage_path,uploader_id,uploader_name,moderation_status,reviewed_at,rejection_reason")
            .order("created_at", ascending: false)
            .execute()

        return response.value.map { $0.marketplaceItem }
    }

    func listDiscoverWallpapers() async throws -> [DiscoverWallpaper] {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        do {
            return try await listDiscoverWallpapers(
                from: client,
                table: configuration.marketplaceTable,
                select: Self.discoverSelectWithProfileHandle
            )
        } catch {
            return try await listDiscoverWallpapers(
                from: client,
                table: configuration.marketplaceTable,
                select: Self.discoverSelectWithProfile
            )
        }
    }

    func listMyUploads(userID: String) async throws -> [DiscoverWallpaper] {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        do {
            return try await listMyUploads(
                from: client,
                table: configuration.marketplaceTable,
                select: Self.discoverSelectWithProfileHandle,
                userID: userID
            )
        } catch {
            return try await listMyUploads(
                from: client,
                table: configuration.marketplaceTable,
                select: Self.discoverSelectWithProfile,
                userID: userID
            )
        }
    }

    private func listDiscoverWallpapers(
        from client: SupabaseClient,
        table: String,
        select: String
    ) async throws -> [DiscoverWallpaper] {
        let response: PostgrestResponse<[SupabaseDiscoverWallpaperRow]> = try await client
            .from(table)
            .select(select)
            .eq("is_hidden", value: false)
            .order("created_at", ascending: false)
            .execute()

        return response.value.map { $0.discoverWallpaper }
    }

    private func listMyUploads(
        from client: SupabaseClient,
        table: String,
        select: String,
        userID: String
    ) async throws -> [DiscoverWallpaper] {
        let response: PostgrestResponse<[SupabaseDiscoverWallpaperRow]> = try await client
            .from(table)
            .select(select)
            .eq("uploader_id", value: userID)
            .order("created_at", ascending: false)
            .execute()

        return response.value.map { $0.discoverWallpaper }
    }

    func incrementDiscoverDownloads(for item: DiscoverWallpaper) async throws -> Int {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseWallpaperDownloadIncrementResult]> = try await client
            .rpc(
                "increment_wallpaper_downloads",
                params: SupabaseWallpaperDownloadIncrementParams(wallpaperID: item.id)
            )
            .execute()

        guard let result = response.value.first else {
            throw MotionDockAuthError.invalidResponse("Download increment did not return a result.")
        }

        return result.downloads
    }

    func listLikedDiscoverWallpaperIDs(userID: String) async throws -> Set<String> {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseWallpaperLikeRow]> = try await client
            .from(Self.wallpaperLikesTable)
            .select("wallpaper_id")
            .eq("user_id", value: userID)
            .execute()

        return Set(response.value.compactMap { $0.wallpaperID.trimmedNonEmpty })
    }

    func toggleDiscoverLike(wallpaperID: String) async throws -> SupabaseWallpaperLikeToggleResult {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseWallpaperLikeToggleResult]> = try await client
            .rpc(
                "toggle_wallpaper_like",
                params: SupabaseWallpaperLikeToggleParams(wallpaperID: wallpaperID)
            )
            .execute()

        guard let result = response.value.first else {
            throw MotionDockAuthError.invalidResponse("Like toggle did not return a result.")
        }

        return result
    }

    func insertR2MarketplaceWallpaper(
        id: String,
        title: String,
        description: String?,
        category: String,
        uploadedAsset: MarketplaceStoredAsset,
        thumbnailAsset: MarketplaceStoredAsset?,
        uploader: MotionDockAuthenticatedUser,
        confirmedRights: Bool
    ) async throws -> DiscoverWallpaper {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let payload = SupabaseDiscoverWallpaperInsert(
            id: id,
            title: title,
            description: description,
            uploaderID: uploader.id,
            thumbnailURL: thumbnailAsset?.publicURL,
            videoURL: uploadedAsset.publicURL,
            category: category,
            downloads: 0,
            likesCount: 0,
            uploaderConfirmedRights: confirmedRights,
            reportCount: 0,
            isHidden: false,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let response: PostgrestResponse<SupabaseDiscoverWallpaperRow> = try await client
            .from(configuration.marketplaceTable)
            .insert(payload, returning: .representation)
            .select(Self.discoverBaseSelect)
            .single()
            .execute()

        return response.value.discoverWallpaper
    }

    func reportWallpaper(
        wallpaperID: String,
        reason: MarketplaceReportReason,
        details: String?
    ) async throws -> SupabaseWallpaperReportResult {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let params = SupabaseWallpaperReportParams(
            wallpaperID: wallpaperID,
            reason: reason.rawValue,
            details: details?.trimmedNonEmpty ?? ""
        )

        NSLog(
            "[MotionDock Marketplace] calling RPC %@ with parameter keys: %@",
            Self.reportWallpaperRPCName,
            Self.reportWallpaperRPCParameterKeys.joined(separator: ", ")
        )

        do {
            let response: PostgrestResponse<[SupabaseWallpaperReportResult]> = try await client
                .rpc(
                    Self.reportWallpaperRPCName,
                    params: params
                )
                .execute()

            guard let result = response.value.first else {
                throw MotionDockAuthError.invalidResponse("Wallpaper report did not return a result.")
            }

            return result
        } catch {
            NSLog(
                "[MotionDock Marketplace] RPC %@ failed with parameter keys %@: %@",
                Self.reportWallpaperRPCName,
                Self.reportWallpaperRPCParameterKeys.joined(separator: ", "),
                error.localizedDescription
            )
            throw error
        }
    }

    func updateProfileDisplayName(
        user: MotionDockAuthenticatedUser,
        displayName: String
    ) async throws -> MotionDockAuthenticatedUser {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let draft = MotionDockProfileDraft(
            id: user.id,
            displayName: displayName.trimmedNonEmpty ?? user.displayName,
            email: user.email?.trimmedNonEmpty,
            avatarUrl: user.avatarUrl?.trimmedNonEmpty
        )
        let payload = SupabaseProfileUpsert(
            id: user.id,
            displayName: draft.displayName,
            email: draft.email,
            avatarUrl: draft.avatarUrl,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let response: PostgrestResponse<SupabaseProfileRow> = try await client
            .from("profiles")
            .upsert(payload, onConflict: "id")
            .select("id,display_name,email,avatar_url")
            .single()
            .execute()

        return response.value.authenticatedUser(fallback: draft)
    }

    func updateMyUploadMetadata(
        wallpaperID: String,
        title: String,
        description: String?,
        category: String
    ) async throws -> DiscoverWallpaper {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseDiscoverWallpaperRow]> = try await client
            .rpc(
                "update_own_wallpaper_metadata",
                params: SupabaseWallpaperMetadataUpdateParams(
                    wallpaperID: wallpaperID,
                    title: title,
                    description: description,
                    category: category
                )
            )
            .execute()

        guard let result = response.value.first else {
            throw MotionDockAuthError.invalidResponse("Wallpaper metadata update did not return a result.")
        }

        return result.discoverWallpaper
    }

    func deleteMyUpload(wallpaperID: String) async throws {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseWallpaperDeleteResult]> = try await client
            .rpc(
                "delete_own_wallpaper",
                params: SupabaseWallpaperDeleteParams(wallpaperID: wallpaperID)
            )
            .execute()

        guard response.value.first?.deleted == true else {
            throw MotionDockAuthError.invalidResponse("Wallpaper delete did not return a result.")
        }
    }

    func uploadMarketplaceWallpaper(
        item: WallpaperLibraryItem,
        fileURL: URL,
        uploader: MotionDockAuthenticatedUser
    ) async throws -> MarketplaceItem {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }
        guard MarketplaceUploadPolicy.isSupported(fileURL: fileURL, kind: item.kind) else {
            throw MarketplaceError.unsupportedUpload
        }

        let id = UUID().uuidString
        let originalFilename = fileURL.lastPathComponent
        let safeFilename = Self.safeFilename(originalFilename)
        let storagePath = "\(uploader.id)/\(id)-\(safeFilename)"
        let kind = item.kind == .gif ? "gif" : "video"
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= MarketplaceUploadPolicy.maxUploadBytes else {
            throw MarketplaceError.uploadTooLarge(limitBytes: MarketplaceUploadPolicy.maxUploadBytes)
        }
        let usedStorageBytes = try await marketplaceStorageBytes(for: uploader.id)
        guard usedStorageBytes + fileSize <= MarketplaceUploadPolicy.maxUserStorageBytes else {
            throw MarketplaceError.userStorageQuotaExceeded(limitBytes: MarketplaceUploadPolicy.maxUserStorageBytes)
        }

        _ = try await client.storage
            .from(configuration.marketplaceBucket)
            .upload(
                storagePath,
                fileURL: fileURL,
                options: FileOptions(
                    cacheControl: "86400",
                    contentType: Self.contentType(for: fileURL),
                    upsert: false
                )
            )

        let payload = SupabaseWallpaperInsert(
            id: id,
            title: item.name,
            kind: kind,
            filename: originalFilename,
            fileSize: fileSize,
            storagePath: storagePath,
            uploaderID: uploader.id,
            uploaderName: uploader.displayName
        )

        let response: PostgrestResponse<SupabaseWallpaperRow> = try await client
            .from(configuration.marketplaceTable)
            .insert(payload, returning: .representation)
            .select("id,title,kind,filename,file_size,created_at,storage_path,uploader_id,uploader_name,moderation_status,reviewed_at,rejection_reason")
            .single()
            .execute()

        return response.value.marketplaceItem
    }

    func downloadMarketplaceWallpaper(_ item: MarketplaceItem) async throws -> Data {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }
        guard let storagePath = item.storagePath?.trimmedNonEmpty else {
            throw MarketplaceError.invalidResponse
        }

        return try await client.storage
            .from(configuration.marketplaceBucket)
            .download(path: storagePath)
    }

    private func syncProfile(
        for user: User,
        preferredProfile: MotionDockProfileDraft?
    ) async throws -> MotionDockAuthenticatedUser {
        guard let client else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let draft = makeProfileDraft(user: user, preferredProfile: preferredProfile)
        let payload = SupabaseProfileUpsert(
            id: user.id.uuidString,
            displayName: draft.displayName,
            email: draft.email,
            avatarUrl: draft.avatarUrl,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let response: PostgrestResponse<SupabaseProfileRow> = try await client
            .from("profiles")
            .upsert(payload, onConflict: "id")
            .select("id,display_name,email,avatar_url")
            .single()
            .execute()

        return response.value.authenticatedUser(fallback: draft)
    }

    private func marketplaceStorageBytes(for uploaderID: String) async throws -> Int {
        guard let client, let configuration else {
            throw configurationError ?? MotionDockAuthError.missingSupabaseConfiguration
        }

        let response: PostgrestResponse<[SupabaseWallpaperRow]> = try await client
            .from(configuration.marketplaceTable)
            .select("id,title,kind,filename,file_size,created_at,storage_path,uploader_id,uploader_name,moderation_status,reviewed_at,rejection_reason")
            .execute()

        return response.value.reduce(0) { total, row in
            guard row.uploaderID == uploaderID else {
                return total
            }
            return total + (row.fileSize ?? 0)
        }
    }

    private func makeProfileDraft(
        user: User,
        preferredProfile: MotionDockProfileDraft?
    ) -> MotionDockProfileDraft {
        let metadataDisplayName = firstString(
            in: user.userMetadata,
            keys: ["display_name", "full_name", "name"]
        )
        let metadataAvatarUrl = firstString(
            in: user.userMetadata,
            keys: ["avatar_url", "picture"]
        )

        let displayName = preferredProfile?.displayName.trimmedNonEmpty
            ?? metadataDisplayName
            ?? user.email?.trimmedNonEmpty
            ?? "MotionDock User"

        return MotionDockProfileDraft(
            id: user.id.uuidString,
            displayName: displayName,
            email: preferredProfile?.email?.trimmedNonEmpty ?? user.email?.trimmedNonEmpty,
            avatarUrl: preferredProfile?.avatarUrl?.trimmedNonEmpty ?? metadataAvatarUrl
        )
    }

    private func firstString(in metadata: [String: AnyJSON], keys: [String]) -> String? {
        for key in keys {
            if let value = metadata[key]?.stringValue?.trimmedNonEmpty {
                return value
            }
        }
        return nil
    }

    private static func contentType(for fileURL: URL) -> String {
        if fileURL.pathExtension.lowercased() == "gif" {
            return "image/gif"
        }

        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private static func safeFilename(_ filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = filename.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return sanitized.isEmpty ? "wallpaper" : sanitized
    }
}

private struct MotionDockProfileDraft: Equatable {
    var id: String
    var displayName: String
    var email: String?
    var avatarUrl: String?
}

private struct SupabaseProfileUpsert: Encodable {
    let id: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
        case updatedAt = "updated_at"
    }
}

private struct SupabaseProfileRow: Decodable {
    let id: String
    let displayName: String?
    let email: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
    }

    func authenticatedUser(fallback: MotionDockProfileDraft) -> MotionDockAuthenticatedUser {
        MotionDockAuthenticatedUser(
            id: id,
            displayName: displayName?.trimmedNonEmpty ?? fallback.displayName,
            email: email?.trimmedNonEmpty ?? fallback.email,
            avatarUrl: avatarUrl?.trimmedNonEmpty ?? fallback.avatarUrl
        )
    }
}

private struct SupabaseWallpaperInsert: Encodable {
    let id: String
    let title: String
    let kind: String
    let filename: String
    let fileSize: Int
    let storagePath: String
    let uploaderID: String
    let uploaderName: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case filename
        case fileSize = "file_size"
        case storagePath = "storage_path"
        case uploaderID = "uploader_id"
        case uploaderName = "uploader_name"
    }
}

private struct SupabaseWallpaperRow: Decodable {
    let id: String
    let title: String
    let kind: String
    let filename: String
    let fileSize: Int?
    let createdAt: String?
    let storagePath: String?
    let uploaderID: String?
    let uploaderName: String?
    let moderationStatus: String?
    let reviewedAt: String?
    let rejectionReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case filename
        case fileSize = "file_size"
        case createdAt = "created_at"
        case storagePath = "storage_path"
        case uploaderID = "uploader_id"
        case uploaderName = "uploader_name"
        case moderationStatus = "moderation_status"
        case reviewedAt = "reviewed_at"
        case rejectionReason = "rejection_reason"
    }

    var marketplaceItem: MarketplaceItem {
        MarketplaceItem(
            id: id,
            title: title,
            kind: kind,
            filename: filename,
            size: fileSize ?? 0,
            createdAt: createdAt ?? "",
            downloadURL: "",
            storagePath: storagePath,
            uploaderName: uploaderName,
            uploaderID: uploaderID,
            moderationStatus: moderationStatus,
            reviewedAt: reviewedAt,
            rejectionReason: rejectionReason
        )
    }
}

private struct SupabaseDiscoverWallpaperRow: Decodable {
    let id: String
    let title: String?
    let description: String?
    let uploaderID: String?
    let profile: SupabaseDiscoverProfileRow?
    let thumbnailURL: String?
    let videoURL: String?
    let category: String?
    let downloads: Int?
    let likesCount: Int?
    let uploaderConfirmedRights: Bool?
    let reportCount: Int?
    let isHidden: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case uploaderID = "uploader_id"
        case profile = "profiles"
        case thumbnailURL = "thumbnail_url"
        case videoURL = "video_url"
        case category
        case downloads
        case likesCount = "likes_count"
        case uploaderConfirmedRights = "uploader_confirmed_rights"
        case reportCount = "report_count"
        case isHidden = "is_hidden"
        case createdAt = "created_at"
    }

    var discoverWallpaper: DiscoverWallpaper {
        DiscoverWallpaper(
            id: id,
            title: title ?? "Untitled Wallpaper",
            description: description,
            uploaderID: uploaderID,
            uploaderDisplayName: profile?.displayNameFallback,
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            category: category,
            downloads: downloads ?? 0,
            likesCount: likesCount ?? 0,
            isLiked: false,
            reportCount: reportCount ?? 0,
            isHidden: isHidden ?? false,
            uploaderConfirmedRights: uploaderConfirmedRights ?? false,
            createdAt: createdAt
        )
    }
}

private struct SupabaseDiscoverProfileRow: Decodable {
    let displayName: String?
    let handle: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handle
        case email
    }

    var displayNameFallback: String? {
        displayName?.trimmedNonEmpty
            ?? handle?.trimmedNonEmpty
            ?? email?.trimmedNonEmpty
    }
}

private struct SupabaseWallpaperLikeRow: Decodable {
    let wallpaperID: String

    enum CodingKeys: String, CodingKey {
        case wallpaperID = "wallpaper_id"
    }
}

private struct SupabaseWallpaperDownloadIncrementParams: Encodable {
    let wallpaperID: String

    enum CodingKeys: String, CodingKey {
        case wallpaperID = "p_wallpaper_id"
    }
}

private struct SupabaseWallpaperDownloadIncrementResult: Decodable {
    let downloads: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            downloads = max(0, value)
            return
        }

        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        downloads = max(0, try keyedContainer.decode(Int.self, forKey: .downloads))
    }

    private enum CodingKeys: String, CodingKey {
        case downloads
    }
}

private struct SupabaseWallpaperReportParams: Encodable {
    let wallpaperID: String
    let reason: String
    let details: String

    enum CodingKeys: String, CodingKey {
        case wallpaperID = "p_wallpaper_id"
        case reason = "p_reason"
        case details = "p_details"
    }
}

struct SupabaseWallpaperReportResult: Decodable, Equatable {
    let reportCount: Int
    let isHidden: Bool

    enum CodingKeys: String, CodingKey {
        case reportCount = "report_count"
        case isHidden = "is_hidden"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reportCount = max(0, try container.decode(Int.self, forKey: .reportCount))
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
    }
}

private struct SupabaseWallpaperMetadataUpdateParams: Encodable {
    let wallpaperID: String
    let title: String
    let description: String?
    let category: String

    enum CodingKeys: String, CodingKey {
        case wallpaperID = "p_wallpaper_id"
        case title = "p_title"
        case description = "p_description"
        case category = "p_category"
    }
}

private struct SupabaseWallpaperDeleteParams: Encodable {
    let wallpaperID: String

    enum CodingKeys: String, CodingKey {
        case wallpaperID = "p_wallpaper_id"
    }
}

private struct SupabaseWallpaperDeleteResult: Decodable {
    let deleted: Bool
}

private struct SupabaseWallpaperLikeToggleParams: Encodable {
    let wallpaperID: String

    enum CodingKeys: String, CodingKey {
        case wallpaperID = "p_wallpaper_id"
    }
}

struct SupabaseWallpaperLikeToggleResult: Decodable, Equatable {
    let liked: Bool
    let likesCount: Int

    enum CodingKeys: String, CodingKey {
        case liked
        case likesCount = "likes_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liked = try container.decode(Bool.self, forKey: .liked)
        likesCount = max(0, try container.decode(Int.self, forKey: .likesCount))
    }
}

private struct SupabaseDiscoverWallpaperInsert: Encodable {
    let id: String
    let title: String
    let description: String?
    let uploaderID: String
    let thumbnailURL: String?
    let videoURL: String
    let category: String
    let downloads: Int
    let likesCount: Int
    let uploaderConfirmedRights: Bool
    let reportCount: Int
    let isHidden: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case uploaderID = "uploader_id"
        case thumbnailURL = "thumbnail_url"
        case videoURL = "video_url"
        case category
        case downloads
        case likesCount = "likes_count"
        case uploaderConfirmedRights = "uploader_confirmed_rights"
        case reportCount = "report_count"
        case isHidden = "is_hidden"
        case createdAt = "created_at"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
