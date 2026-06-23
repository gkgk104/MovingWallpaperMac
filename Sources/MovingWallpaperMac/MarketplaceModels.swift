import Foundation

enum MarketplaceUploadPolicy {
    static let maxUploadMegabytes = 250
    static let maxUploadBytes = maxUploadMegabytes * 1024 * 1024
    static let maxUserStorageMegabytes = 1024
    static let maxUserStorageBytes = maxUserStorageMegabytes * 1024 * 1024
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let supportedR2UploadExtensions: Set<String> = ["mp4", "mov"]
    static let supportedGIFExtensions: Set<String> = ["gif"]
    static let supportedFileTypesText = "MP4, MOV, M4V, and GIF"
    static let supportedR2UploadTypesText = "MP4 and MOV"

    static func isSupported(fileURL: URL, kind: WallpaperItemKind) -> Bool {
        let fileExtension = fileURL.pathExtension.lowercased()
        switch kind {
        case .video:
            return supportedVideoExtensions.contains(fileExtension)
        case .gif:
            return supportedGIFExtensions.contains(fileExtension)
        case .motion, .web:
            return false
        }
    }

    static func isSupportedR2Upload(fileURL: URL) -> Bool {
        supportedR2UploadExtensions.contains(fileURL.pathExtension.lowercased())
    }

    static func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

enum MarketplaceCategory: String, CaseIterable, Identifiable {
    case cinematic = "Cinematic"
    case nature = "Nature"
    case space = "Space"
    case anime = "Anime"
    case abstract = "Abstract"
    case cars = "Cars"
    case city = "City"
    case minimal = "Minimal"
    case game = "Game"
    case other = "Other"

    var id: String {
        rawValue
    }
}

enum MarketplaceUploadTerms {
    static let title = "MotionDock Marketplace Upload Terms"
    static let subtitle = "User Responsibility"
    static let body = """
By uploading content to MotionDock Marketplace, you confirm and agree that:

1. You own the rights to the wallpaper you upload or have obtained all necessary permissions from the copyright owner.
2. You are solely responsible for any legal issues arising from your uploaded content, including but not limited to:

* Copyright infringement
* Portrait rights or publicity rights violations
* Unauthorized use of trademarks or intellectual property
* Adult or sexually explicit content
* Illegal or harmful content
* Spam or malicious content
* Any other content that violates applicable laws or third-party rights

3. MotionDock does not pre-screen or manually review wallpapers before publication.
4. MotionDock reserves the right to remove, hide, restrict, or delete any content that receives reports or is found to violate these Terms.
5. Users may report wallpapers that violate copyright, portrait rights, laws, or community standards.
6. Repeated reports or violations may result in automatic hiding of the content and may lead to suspension or termination of the uploader’s account.
7. MotionDock is a platform service and does not claim ownership of user-uploaded content. The uploader retains ownership and bears full responsibility for the content they publish.
8. By uploading content, you acknowledge and agree to these Terms and understand that you are responsible for any damages, claims, or disputes caused by your uploads.
"""
    static let shortConsent = "I confirm that I own the rights to this wallpaper or have permission to upload it. I understand that I am responsible for copyright, portrait rights, adult content, illegal content, and any other issues caused by this upload. MotionDock may hide or remove reported content without prior notice."
}

enum MarketplaceReportReason: String, CaseIterable, Identifiable {
    case copyright = "Copyright"
    case portraitRights = "Portrait Rights"
    case adultContent = "Adult Content"
    case illegalContent = "Illegal Content"
    case spam = "Spam"
    case other = "Other"

    var id: String {
        rawValue
    }
}

struct MarketplaceItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let kind: String
    let filename: String
    let size: Int
    let createdAt: String
    let downloadURL: String
    let storagePath: String?
    let uploaderName: String?
    let uploaderID: String?
    let moderationStatus: String?
    let reviewedAt: String?
    let rejectionReason: String?

    init(
        id: String,
        title: String,
        kind: String,
        filename: String,
        size: Int,
        createdAt: String,
        downloadURL: String,
        storagePath: String? = nil,
        uploaderName: String?,
        uploaderID: String?,
        moderationStatus: String? = nil,
        reviewedAt: String? = nil,
        rejectionReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.filename = filename
        self.size = size
        self.createdAt = createdAt
        self.downloadURL = downloadURL
        self.storagePath = storagePath
        self.uploaderName = uploaderName
        self.uploaderID = uploaderID
        self.moderationStatus = moderationStatus
        self.reviewedAt = reviewedAt
        self.rejectionReason = rejectionReason
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case filename
        case size
        case createdAt
        case downloadURL
        case storagePath
        case storageSnakePath = "storage_path"
        case uploaderName
        case uploaderID
        case uploaderSnakeID = "uploader_id"
        case moderationStatus
        case moderationSnakeStatus = "moderation_status"
        case reviewedAt
        case reviewedSnakeAt = "reviewed_at"
        case rejectionReason
        case rejectionSnakeReason = "rejection_reason"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(String.self, forKey: .kind)
        filename = try container.decode(String.self, forKey: .filename)
        size = try container.decode(Int.self, forKey: .size)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL) ?? ""
        storagePath = try container.decodeIfPresent(String.self, forKey: .storageSnakePath)
            ?? container.decodeIfPresent(String.self, forKey: .storagePath)
        uploaderName = try container.decodeIfPresent(String.self, forKey: .uploaderName)
        uploaderID = try container.decodeIfPresent(String.self, forKey: .uploaderSnakeID)
            ?? container.decodeIfPresent(String.self, forKey: .uploaderID)
        moderationStatus = try container.decodeIfPresent(String.self, forKey: .moderationSnakeStatus)
            ?? container.decodeIfPresent(String.self, forKey: .moderationStatus)
        reviewedAt = try container.decodeIfPresent(String.self, forKey: .reviewedSnakeAt)
            ?? container.decodeIfPresent(String.self, forKey: .reviewedAt)
        rejectionReason = try container.decodeIfPresent(String.self, forKey: .rejectionSnakeReason)
            ?? container.decodeIfPresent(String.self, forKey: .rejectionReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(filename, forKey: .filename)
        try container.encode(size, forKey: .size)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(downloadURL, forKey: .downloadURL)
        try container.encodeIfPresent(storagePath, forKey: .storageSnakePath)
        try container.encodeIfPresent(uploaderName, forKey: .uploaderName)
        try container.encodeIfPresent(uploaderID, forKey: .uploaderSnakeID)
        try container.encodeIfPresent(moderationStatus, forKey: .moderationSnakeStatus)
        try container.encodeIfPresent(reviewedAt, forKey: .reviewedSnakeAt)
        try container.encodeIfPresent(rejectionReason, forKey: .rejectionSnakeReason)
    }

    var supportedKind: WallpaperItemKind? {
        switch kind {
        case "video":
            return .video
        case "gif":
            return .gif
        default:
            return nil
        }
    }

    var detail: String {
        "\(kind.uppercased()) · \(filename) · \(Self.formattedSize(size))"
    }

    var uploaderDisplayText: String {
        let trimmed = uploaderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    var moderationStatusValue: MarketplaceModerationStatus {
        MarketplaceModerationStatus(rawValue: moderationStatus?.lowercased() ?? "")
            ?? .approved
    }

    private static func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct DiscoverWallpaper: Equatable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let uploaderID: String?
    let uploaderDisplayName: String?
    let thumbnailURL: String?
    let videoURL: String?
    let category: String?
    let downloads: Int
    let likesCount: Int
    let isLiked: Bool
    let reportCount: Int
    let isHidden: Bool
    let uploaderConfirmedRights: Bool
    let createdAt: String?

    var displayTitle: String {
        trimmed(title) ?? "Untitled Wallpaper"
    }

    var descriptionText: String {
        trimmed(description) ?? "No description provided."
    }

    var categoryText: String {
        trimmed(category) ?? "Wallpaper"
    }

    var thumbnailURLValue: URL? {
        guard let thumbnailURL = trimmed(thumbnailURL) else {
            return nil
        }
        return URL(string: thumbnailURL)
    }

    var videoURLValue: URL? {
        guard let videoURL = trimmed(videoURL) else {
            return nil
        }
        return URL(string: videoURL)
    }

    var hasDownloadableVideo: Bool {
        videoURLValue != nil
    }

    var uploaderText: String {
        trimmed(uploaderDisplayName) ?? "Unknown"
    }

    var createdAtText: String {
        MarketplaceRelativeDateFormatter.displayText(for: createdAt)
    }

    func withDownloads(_ downloads: Int) -> DiscoverWallpaper {
        DiscoverWallpaper(
            id: id,
            title: title,
            description: description,
            uploaderID: uploaderID,
            uploaderDisplayName: uploaderDisplayName,
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            category: category,
            downloads: downloads,
            likesCount: likesCount,
            isLiked: isLiked,
            reportCount: reportCount,
            isHidden: isHidden,
            uploaderConfirmedRights: uploaderConfirmedRights,
            createdAt: createdAt
        )
    }

    func withLikeState(isLiked: Bool, likesCount: Int) -> DiscoverWallpaper {
        DiscoverWallpaper(
            id: id,
            title: title,
            description: description,
            uploaderID: uploaderID,
            uploaderDisplayName: uploaderDisplayName,
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            category: category,
            downloads: downloads,
            likesCount: max(0, likesCount),
            isLiked: isLiked,
            reportCount: reportCount,
            isHidden: isHidden,
            uploaderConfirmedRights: uploaderConfirmedRights,
            createdAt: createdAt
        )
    }

    func withReportState(reportCount: Int, isHidden: Bool) -> DiscoverWallpaper {
        DiscoverWallpaper(
            id: id,
            title: title,
            description: description,
            uploaderID: uploaderID,
            uploaderDisplayName: uploaderDisplayName,
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            category: category,
            downloads: downloads,
            likesCount: likesCount,
            isLiked: isLiked,
            reportCount: max(0, reportCount),
            isHidden: isHidden,
            uploaderConfirmedRights: uploaderConfirmedRights,
            createdAt: createdAt
        )
    }

    private func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

private enum MarketplaceRelativeDateFormatter {
    static func displayText(for rawValue: String?) -> String {
        guard let date = parse(rawValue) else {
            return "Unknown"
        }

        let now = Date()
        let seconds = max(0, Int(now.timeIntervalSince(date)))

        if seconds < 60 {
            return "Just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }

        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        if days > 0 && days < 7 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }

        return absoluteDateFormatter.string(from: date)
    }

    private static func parse(_ rawValue: String?) -> Date? {
        let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawValue.isEmpty else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: rawValue) {
            return date
        }

        for format in fallbackDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }

    private static let fallbackDateFormats = [
        "yyyy-MM-dd HH:mm:ssXXXXX",
        "yyyy-MM-dd HH:mm:ssXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    ]

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

enum MarketplaceModerationStatus: String {
    case pending
    case approved
    case rejected

    var displayText: String {
        switch self {
        case .pending:
            return "Pending Review"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        }
    }

    var allowsDownload: Bool {
        self == .approved
    }
}

enum MarketplaceError: LocalizedError {
    case invalidServerURL
    case unsupportedUpload
    case uploadTooLarge(limitBytes: Int)
    case userStorageQuotaExceeded(limitBytes: Int)
    case unsupportedDownload
    case missingLocalFile
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The marketplace server URL is invalid."
        case .unsupportedUpload:
            return "Marketplace uploads support \(MarketplaceUploadPolicy.supportedFileTypesText)."
        case .uploadTooLarge(let limitBytes):
            return "Marketplace uploads are limited to \(MarketplaceUploadPolicy.formattedSize(limitBytes))."
        case .userStorageQuotaExceeded(let limitBytes):
            return "Marketplace user storage is limited to \(MarketplaceUploadPolicy.formattedSize(limitBytes))."
        case .unsupportedDownload:
            return "This marketplace item is not supported."
        case .missingLocalFile:
            return "The local file could not be found."
        case .invalidResponse:
            return "The marketplace server response could not be read."
        case .server(let message):
            return message
        }
    }
}

struct MarketplaceServerError: Decodable {
    let error: String
}
