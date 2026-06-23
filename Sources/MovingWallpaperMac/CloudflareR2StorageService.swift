import CryptoKit
import Foundation

struct MarketplaceStoredAsset {
    let objectKey: String
    let publicURL: String
    let contentType: String
    let fileSize: Int
}

protocol MarketplaceStorageService {
    func uploadWallpaper(fileURL: URL, objectID: String) async throws -> MarketplaceStoredAsset
    func uploadThumbnail(fileURL: URL, objectID: String) async throws -> MarketplaceStoredAsset
    func deleteAssets(for item: DiscoverWallpaper) async throws
}

enum CloudflareR2StorageError: LocalizedError {
    case missingEnvironment([String])
    case invalidURL(String)
    case invalidObjectKey(String)
    case invalidResponse
    case uploadFailed(statusCode: Int, message: String)
    case deleteFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironment(let keys):
            return "Cloudflare R2 is not configured. Missing: \(keys.joined(separator: ", "))."
        case .invalidURL(let value):
            return "Cloudflare R2 URL is invalid: \(value)."
        case .invalidObjectKey(let value):
            return "Cloudflare R2 object key could not be derived from URL: \(value)."
        case .invalidResponse:
            return "Cloudflare R2 returned an invalid response."
        case .uploadFailed(let statusCode, let message):
            return "Cloudflare R2 upload failed with HTTP \(statusCode): \(message)"
        case .deleteFailed(let statusCode, let message):
            return "Cloudflare R2 delete failed with HTTP \(statusCode): \(message)"
        }
    }
}

final class CloudflareR2StorageService: MarketplaceStorageService {
    struct Configuration {
        let endpoint: URL
        let accessKeyID: String
        let secretAccessKey: String
        let bucket: String
        let publicBaseURL: URL
        let prefix: String
        let region: String

        static func load(
            from environment: [String: String] = ProcessInfo.processInfo.environment
        ) throws -> Configuration {
            let requiredValues = [
                "MOTIONDOCK_R2_ENDPOINT": environment["MOTIONDOCK_R2_ENDPOINT"]?.trimmedNonEmpty,
                "MOTIONDOCK_R2_ACCESS_KEY_ID": environment["MOTIONDOCK_R2_ACCESS_KEY_ID"]?.trimmedNonEmpty,
                "MOTIONDOCK_R2_SECRET_ACCESS_KEY": environment["MOTIONDOCK_R2_SECRET_ACCESS_KEY"]?.trimmedNonEmpty,
                "MOTIONDOCK_R2_BUCKET": environment["MOTIONDOCK_R2_BUCKET"]?.trimmedNonEmpty,
                "MOTIONDOCK_R2_PUBLIC_BASE_URL": environment["MOTIONDOCK_R2_PUBLIC_BASE_URL"]?.trimmedNonEmpty
            ]
            let missingKeys = requiredValues
                .filter { $0.value == nil }
                .map(\.key)
                .sorted()

            guard missingKeys.isEmpty else {
                throw CloudflareR2StorageError.missingEnvironment(missingKeys)
            }

            guard
                let endpointValue = requiredValues["MOTIONDOCK_R2_ENDPOINT"] ?? nil,
                let endpoint = URL(string: endpointValue)
            else {
                throw CloudflareR2StorageError.invalidURL(
                    (requiredValues["MOTIONDOCK_R2_ENDPOINT"] ?? nil) ?? "MOTIONDOCK_R2_ENDPOINT"
                )
            }

            guard
                let publicBaseValue = requiredValues["MOTIONDOCK_R2_PUBLIC_BASE_URL"] ?? nil,
                let publicBaseURL = URL(string: publicBaseValue)
            else {
                throw CloudflareR2StorageError.invalidURL(
                    (requiredValues["MOTIONDOCK_R2_PUBLIC_BASE_URL"] ?? nil) ?? "MOTIONDOCK_R2_PUBLIC_BASE_URL"
                )
            }

            guard
                let accessKeyID = requiredValues["MOTIONDOCK_R2_ACCESS_KEY_ID"] ?? nil,
                let secretAccessKey = requiredValues["MOTIONDOCK_R2_SECRET_ACCESS_KEY"] ?? nil,
                let bucket = requiredValues["MOTIONDOCK_R2_BUCKET"] ?? nil
            else {
                throw CloudflareR2StorageError.missingEnvironment([
                    "MOTIONDOCK_R2_ACCESS_KEY_ID",
                    "MOTIONDOCK_R2_BUCKET",
                    "MOTIONDOCK_R2_SECRET_ACCESS_KEY"
                ])
            }

            return Configuration(
                endpoint: endpoint,
                accessKeyID: accessKeyID,
                secretAccessKey: secretAccessKey,
                bucket: bucket,
                publicBaseURL: publicBaseURL,
                prefix: environment["MOTIONDOCK_R2_PREFIX"]?.trimmedNonEmpty ?? "wallpapers",
                region: environment["MOTIONDOCK_R2_REGION"]?.trimmedNonEmpty ?? "auto"
            )
        }
    }

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    convenience init() throws {
        try self.init(configuration: .load())
    }

    func uploadWallpaper(fileURL: URL, objectID: String) async throws -> MarketplaceStoredAsset {
        let data = try Data(contentsOf: fileURL)
        let contentType = Self.contentType(for: fileURL)
        let objectKey = normalizedObjectKey(prefix: configuration.prefix, objectID: objectID)
        return try await uploadObject(data: data, objectKey: objectKey, contentType: contentType)
    }

    func uploadThumbnail(fileURL: URL, objectID: String) async throws -> MarketplaceStoredAsset {
        let data = try Data(contentsOf: fileURL)
        let objectKey = "thumbnails/\(objectID).jpg"
        return try await uploadObject(data: data, objectKey: objectKey, contentType: "image/jpeg")
    }

    func deleteAssets(for item: DiscoverWallpaper) async throws {
        guard let videoObjectKey = try objectKey(fromPublicURL: item.videoURL) else {
            throw CloudflareR2StorageError.invalidObjectKey(item.videoURL ?? "missing video_url")
        }

        var objectKeys = [videoObjectKey]
        if let thumbnailObjectKey = try objectKey(fromPublicURL: item.thumbnailURL) {
            objectKeys.append(thumbnailObjectKey)
        }

        for objectKey in Set(objectKeys) {
            try await deleteObject(objectKey: objectKey)
        }
    }

    private func uploadObject(
        data: Data,
        objectKey: String,
        contentType: String
    ) async throws -> MarketplaceStoredAsset {
        let uploadURL = try objectURL(for: objectKey)
        let payloadHash = Self.sha256Hex(data)
        let now = Date()
        let amzDate = Self.amzDateFormatter.string(from: now)
        let shortDate = Self.shortDateFormatter.string(from: now)
        let host = try hostHeaderValue()
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalURI = canonicalPath(for: objectKey)
        let canonicalHeaders = [
            "content-type:\(contentType)",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"
        let canonicalRequest = [
            "PUT",
            canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        let credentialScope = "\(shortDate)/\(configuration.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            Self.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")
        let signingKey = Self.signingKey(
            secretAccessKey: configuration.secretAccessKey,
            date: shortDate,
            region: configuration.region
        )
        let signature = Self.hmacSHA256Hex(key: signingKey, message: stringToSign)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(configuration.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudflareR2StorageError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "No response body"
            throw CloudflareR2StorageError.uploadFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        return MarketplaceStoredAsset(
            objectKey: objectKey,
            publicURL: publicURL(for: objectKey).absoluteString,
            contentType: contentType,
            fileSize: data.count
        )
    }

    private func deleteObject(objectKey: String) async throws {
        let deleteURL = try objectURL(for: objectKey)
        let payloadHash = Self.sha256Hex(Data())
        let now = Date()
        let amzDate = Self.amzDateFormatter.string(from: now)
        let shortDate = Self.shortDateFormatter.string(from: now)
        let host = try hostHeaderValue()
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"
        let canonicalRequest = [
            "DELETE",
            canonicalPath(for: objectKey),
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        let credentialScope = "\(shortDate)/\(configuration.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            Self.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")
        let signingKey = Self.signingKey(
            secretAccessKey: configuration.secretAccessKey,
            date: shortDate,
            region: configuration.region
        )
        let signature = Self.hmacSHA256Hex(key: signingKey, message: stringToSign)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(configuration.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudflareR2StorageError.invalidResponse
        }

        guard [200, 202, 204].contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "No response body"
            throw CloudflareR2StorageError.deleteFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    private func normalizedObjectKey(prefix: String, objectID: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filename = "\(objectID).mp4"
        return trimmedPrefix.isEmpty ? filename : "\(trimmedPrefix)/\(filename)"
    }

    private func objectURL(for objectKey: String) throws -> URL {
        var components = URLComponents(url: configuration.endpoint, resolvingAgainstBaseURL: false)
        guard components?.host != nil else {
            throw CloudflareR2StorageError.invalidURL(configuration.endpoint.absoluteString)
        }
        components?.percentEncodedPath = canonicalPath(for: objectKey)
        guard let url = components?.url else {
            throw CloudflareR2StorageError.invalidURL(configuration.endpoint.absoluteString)
        }
        return url
    }

    private func publicURL(for objectKey: String) -> URL {
        var components = URLComponents(url: configuration.publicBaseURL, resolvingAgainstBaseURL: false)
        let baseSegments = configuration.publicBaseURL.path
            .split(separator: "/")
            .map(String.init)
        let keySegments = objectKey
            .split(separator: "/")
            .map(String.init)
        components?.percentEncodedPath = "/" + (baseSegments + keySegments)
            .map(Self.awsPercentEncode)
            .joined(separator: "/")
        return components?.url ?? configuration.publicBaseURL.appendingPathComponent(objectKey)
    }

    private func objectKey(fromPublicURL rawURL: String?) throws -> String? {
        guard let rawURL = rawURL?.trimmedNonEmpty else {
            return nil
        }
        guard let url = URL(string: rawURL) else {
            throw CloudflareR2StorageError.invalidURL(rawURL)
        }
        guard url.scheme == configuration.publicBaseURL.scheme,
              url.host == configuration.publicBaseURL.host else {
            throw CloudflareR2StorageError.invalidObjectKey(rawURL)
        }

        let basePath = configuration.publicBaseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var objectPath = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if !basePath.isEmpty {
            guard objectPath == basePath || objectPath.hasPrefix("\(basePath)/") else {
                throw CloudflareR2StorageError.invalidObjectKey(rawURL)
            }
            objectPath.removeFirst(basePath.count)
            objectPath = objectPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard !objectPath.isEmpty else {
            return nil
        }

        return objectPath.removingPercentEncoding ?? objectPath
    }

    private func canonicalPath(for objectKey: String) -> String {
        let endpointSegments = configuration.endpoint.path
            .split(separator: "/")
            .map(String.init)
        let pathSegments = endpointSegments
            + [configuration.bucket]
            + objectKey.split(separator: "/").map(String.init)
        return "/" + pathSegments.map(Self.awsPercentEncode).joined(separator: "/")
    }

    private func hostHeaderValue() throws -> String {
        guard let host = configuration.endpoint.host?.trimmedNonEmpty else {
            throw CloudflareR2StorageError.invalidURL(configuration.endpoint.absoluteString)
        }

        if let port = configuration.endpoint.port {
            return "\(host):\(port)"
        }
        return host
    }

    private static func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "mov":
            return "video/quicktime"
        default:
            return "video/mp4"
        }
    }

    private static func signingKey(secretAccessKey: String, date: String, region: String) -> SymmetricKey {
        let dateKey = hmacSHA256Data(
            key: SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8)),
            message: date
        )
        let regionKey = hmacSHA256Data(key: SymmetricKey(data: dateKey), message: region)
        let serviceKey = hmacSHA256Data(key: SymmetricKey(data: regionKey), message: "s3")
        let signingKey = hmacSHA256Data(key: SymmetricKey(data: serviceKey), message: "aws4_request")
        return SymmetricKey(data: signingKey)
    }

    private static func hmacSHA256Data(key: SymmetricKey, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
    }

    private static func hmacSHA256Hex(key: SymmetricKey, message: String) -> String {
        hmacSHA256Data(key: key, message: message).hexString
    }

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hexString
    }

    private static func awsPercentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
