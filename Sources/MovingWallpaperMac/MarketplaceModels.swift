import Foundation

struct MarketplaceItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let kind: String
    let filename: String
    let size: Int
    let createdAt: String
    let downloadURL: String
    let uploaderName: String?
    let uploaderID: String?

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

    private static func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

enum MarketplaceError: LocalizedError {
    case invalidServerURL
    case unsupportedUpload
    case unsupportedDownload
    case missingLocalFile
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The marketplace server URL is invalid."
        case .unsupportedUpload:
            return "Marketplace uploads support local video files and GIFs."
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
