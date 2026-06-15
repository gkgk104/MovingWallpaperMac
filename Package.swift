// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MovingWallpaperMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MovingWallpaperMac", targets: ["MovingWallpaperMac"])
    ],
    targets: [
        .executableTarget(
            name: "MovingWallpaperMac",
            path: "Sources/MovingWallpaperMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
