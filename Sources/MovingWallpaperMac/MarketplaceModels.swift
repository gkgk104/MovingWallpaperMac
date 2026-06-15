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
        return trimmed.isEmpty ? "알 수 없음" : trimmed
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
            return "마켓플레이스 서버 주소가 올바르지 않습니다."
        case .unsupportedUpload:
            return "마켓플레이스 업로드는 로컬 동영상과 GIF만 지원합니다."
        case .unsupportedDownload:
            return "이 마켓플레이스 항목은 현재 앱에서 지원하지 않는 형식입니다."
        case .missingLocalFile:
            return "업로드할 로컬 파일을 찾을 수 없습니다."
        case .invalidResponse:
            return "마켓플레이스 서버 응답을 읽을 수 없습니다."
        case .server(let message):
            return message
        }
    }
}

struct MarketplaceServerError: Decodable {
    let error: String
}
