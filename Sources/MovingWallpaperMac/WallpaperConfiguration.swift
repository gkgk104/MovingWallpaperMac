import AVFoundation
import Foundation

enum WallpaperItemKind: String, Codable, CaseIterable, Identifiable {
    case motion
    case video
    case gif
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .motion:
            "Motion"
        case .video:
            "Video"
        case .gif:
            "GIF"
        case .web:
            "Web"
        }
    }

    var systemImage: String {
        switch self {
        case .motion:
            "sparkles"
        case .video:
            "film"
        case .gif:
            "photo.on.rectangle"
        case .web:
            "globe"
        }
    }
}

enum MotionScene: String, Codable, CaseIterable, Identifiable {
    case aurora
    case orbit
    case mesh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aurora:
            "Aurora Ribbons"
        case .orbit:
            "Orbit Flow"
        case .mesh:
            "Signal Mesh"
        }
    }
}

enum MotionPalette: String, Codable, CaseIterable, Identifiable {
    case aurora
    case ember
    case graphite
    case prism

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aurora:
            "Aurora"
        case .ember:
            "Ember"
        case .graphite:
            "Graphite"
        case .prism:
            "Prism"
        }
    }
}

enum VideoFillMode: String, CaseIterable, Identifiable {
    case cover
    case fit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cover:
            "Fill"
        case .fit:
            "Fit"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .cover:
            .resizeAspectFill
        case .fit:
            .resizeAspect
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case allDisplays
    case mainDisplay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allDisplays:
            "All Displays"
        case .mainDisplay:
            "Main Display"
        }
    }
}

enum PerformanceProfile: String, Codable, CaseIterable, Identifiable {
    case quality
    case balanced
    case batterySaver

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality:
            "Quality"
        case .balanced:
            "Balanced"
        case .batterySaver:
            "Low Power"
        }
    }

    var motionFrameInterval: TimeInterval {
        switch self {
        case .quality:
            1.0 / 60.0
        case .balanced:
            1.0 / 30.0
        case .batterySaver:
            1.0 / 15.0
        }
    }

    var motionSpeedScale: Double {
        switch self {
        case .quality:
            1.0
        case .balanced:
            0.82
        case .batterySaver:
            0.58
        }
    }
}

enum PerformancePolicy: String, Codable, CaseIterable, Identifiable {
    case keepRunning
    case pauseWhenCovered
    case stopWhenCovered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keepRunning:
            "Always Play"
        case .pauseWhenCovered:
            "Pause When Covered"
        case .stopWhenCovered:
            "Stop When Covered"
        }
    }
}

struct WallpaperLibraryItem: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: WallpaperItemKind
    var videoPath: String?
    var webURLString: String?
    var motionScene: MotionScene
    var motionPalette: MotionPalette
    var isBuiltIn: Bool

    var detail: String {
        switch kind {
        case .motion:
            return "\(motionScene.label) · \(motionPalette.label)"
        case .video:
            guard let videoPath else {
                return "Local Video"
            }
            return URL(fileURLWithPath: videoPath).lastPathComponent
        case .gif:
            guard let videoPath else {
                return "Local GIF"
            }
            return URL(fileURLWithPath: videoPath).lastPathComponent
        case .web:
            return webURLString ?? "Web URL"
        }
    }

    static let defaults: [WallpaperLibraryItem] = [
        WallpaperLibraryItem(
            id: "motion-aurora",
            name: "Aurora Ribbons",
            kind: .motion,
            videoPath: nil,
            webURLString: nil,
            motionScene: .aurora,
            motionPalette: .aurora,
            isBuiltIn: true
        ),
        WallpaperLibraryItem(
            id: "motion-orbit",
            name: "Orbit Flow",
            kind: .motion,
            videoPath: nil,
            webURLString: nil,
            motionScene: .orbit,
            motionPalette: .prism,
            isBuiltIn: true
        ),
        WallpaperLibraryItem(
            id: "motion-mesh",
            name: "Signal Mesh",
            kind: .motion,
            videoPath: nil,
            webURLString: nil,
            motionScene: .mesh,
            motionPalette: .graphite,
            isBuiltIn: true
        )
    ]
}

enum WallpaperSource {
    case motion(scene: MotionScene, palette: MotionPalette)
    case video(URL)
    case gif(URL)
    case web(URL)
}

struct WallpaperConfiguration {
    let item: WallpaperLibraryItem
    let source: WallpaperSource
    let muted: Bool
    let fillMode: VideoFillMode
    let displayMode: DisplayMode
    let performanceProfile: PerformanceProfile
}
