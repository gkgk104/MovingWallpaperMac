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
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MovingWallpaperMac",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/MovingWallpaperMac",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
