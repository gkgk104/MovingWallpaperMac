import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private struct WallpaperThumbnailRequest: Sendable {
    let key: String
    let kindRawValue: String
    let path: String
}

@MainActor
final class WallpaperThumbnailStore: ObservableObject {
    @Published private var thumbnails: [String: NSImage] = [:]
    private var loadingKeys: Set<String> = []

    nonisolated static func cacheKey(for item: WallpaperLibraryItem) -> String {
        [item.id, item.kind.rawValue, item.videoPath ?? ""].joined(separator: "|")
    }

    func thumbnail(for item: WallpaperLibraryItem) -> NSImage? {
        thumbnails[Self.cacheKey(for: item)]
    }

    func requestThumbnail(for item: WallpaperLibraryItem) {
        guard let request = Self.thumbnailRequest(for: item) else {
            return
        }

        guard thumbnails[request.key] == nil, !loadingKeys.contains(request.key) else {
            return
        }

        loadingKeys.insert(request.key)

        let renderTask = Task.detached(priority: .utility) {
            WallpaperThumbnailRenderer.renderData(for: request)
        }

        Task { @MainActor in
            let data = await renderTask.value
            if let data, let image = NSImage(data: data) {
                thumbnails[request.key] = image
            }
            loadingKeys.remove(request.key)
        }
    }

    private nonisolated static func thumbnailRequest(for item: WallpaperLibraryItem) -> WallpaperThumbnailRequest? {
        guard item.kind == .video || item.kind == .gif else {
            return nil
        }

        guard let path = item.videoPath, FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return WallpaperThumbnailRequest(
            key: cacheKey(for: item),
            kindRawValue: item.kind.rawValue,
            path: path
        )
    }
}

private enum WallpaperThumbnailRenderer {
    static func renderData(for request: WallpaperThumbnailRequest) -> Data? {
        switch WallpaperItemKind(rawValue: request.kindRawValue) {
        case .video:
            return renderVideoThumbnail(path: request.path)
        case .gif:
            return renderGIFThumbnail(path: request.path)
        case .motion, .web, .none:
            return nil
        }
    }

    private static func renderVideoThumbnail(path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 420)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)

        let preferredTime = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let image = try? generator.copyCGImage(at: preferredTime, actualTime: nil) {
            return pngData(from: image)
        }

        if let image = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            return pngData(from: image)
        }

        return nil
    }

    private static func renderGIFThumbnail(path: String) -> Data? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720
        ]

        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)

        guard let image else {
            return nil
        }

        return pngData(from: image)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
