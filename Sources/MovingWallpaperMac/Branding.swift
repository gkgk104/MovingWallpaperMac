import AppKit
import SwiftUI

enum MotionDockBrand {
    static let appName = "MotionDock"
    static let tagline = "Live wallpapers, made native for macOS."
    static let logoAssetName = "MotionDockLogo"
    static let wordmarkAssetName = "MotionDockWordmark"
    static let appIconAssetName = "MotionDockAppIcon"
    static let logoSubdirectory = "Assets.xcassets/Brand/MotionDockLogo.imageset"
    static let wordmarkSubdirectory = "Assets.xcassets/Brand/MotionDockWordmark.imageset"
    static let menuBarIconSubdirectory = "Assets.xcassets/Brand/MotionDockMenuBarIcon.imageset"
    static let appIconSubdirectory = "Assets.xcassets/AppIcon.appiconset"

    static let background = Color(red: 16.0 / 255.0, green: 17.0 / 255.0, blue: 19.0 / 255.0)
    static let secondarySurface = Color(red: 21.0 / 255.0, green: 22.0 / 255.0, blue: 26.0 / 255.0)
    static let card = Color(red: 28.0 / 255.0, green: 29.0 / 255.0, blue: 33.0 / 255.0)
    static let accent = Color(red: 10.0 / 255.0, green: 132.0 / 255.0, blue: 255.0 / 255.0)
    static let cyanHighlight = Color(red: 48.0 / 255.0, green: 213.0 / 255.0, blue: 255.0 / 255.0)
    static let success = Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)

    static func logoImage() -> NSImage? {
        if let image = NSImage(named: logoAssetName) {
            return image
        }

        return imageResource(named: "motiondock-logo", subdirectory: logoSubdirectory)
            ?? imageResource(named: "motiondock-logo-mark-placeholder@2x", subdirectory: logoSubdirectory)
    }

    static func wordmarkImage() -> NSImage? {
        NSImage(named: wordmarkAssetName)
            ?? imageResource(named: "motiondock-wordmark", subdirectory: wordmarkSubdirectory)
            ?? imageResource(named: "motiondock-wordmark@2x", subdirectory: wordmarkSubdirectory)
    }

    static func statusBarIcon() -> NSImage? {
        let source = imageResource(named: "motiondock-menu-bar-icon", subdirectory: menuBarIconSubdirectory)
            ?? imageResource(named: "motiondock-menu-bar-icon@2x", subdirectory: menuBarIconSubdirectory)
            ?? NSImage(named: appIconAssetName)
            ?? imageResource(named: "motiondock-app-icon", subdirectory: "Assets.xcassets/MotionDockAppIcon.imageset")
            ?? imageResource(named: "icon_32x32@2x", subdirectory: appIconSubdirectory)
            ?? NSImage(named: NSImage.applicationIconName)

        guard let source else {
            return nil
        }

        let image = source.copy() as? NSImage ?? source
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = appName
        return image
    }

    private static func imageResource(named name: String, subdirectory: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdirectory) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct MotionDockBrandLockup: View {
    var logoSize: CGFloat = 58
    var showsTagline = true

    var body: some View {
        HStack(spacing: 14) {
            MotionDockLogoView(size: logoSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(MotionDockBrand.appName)
                    .font(.system(size: logoSize > 54 ? 26 : 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                if showsTagline {
                    Text(MotionDockBrand.tagline)
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(2)
                }
            }
        }
    }
}

struct MotionDockLogoImage: View {
    var body: some View {
        if let image = MotionDockBrand.logoImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(MotionDockBrand.appName)
        } else {
            Color.clear
                .accessibilityLabel("MotionDock logo asset missing")
        }
    }
}

struct MotionDockWordmarkImage: View {
    var body: some View {
        if let image = MotionDockBrand.wordmarkImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("\(MotionDockBrand.appName), \(MotionDockBrand.tagline)")
        } else {
            Color.clear
                .accessibilityLabel("MotionDock wordmark asset missing")
        }
    }
}

struct MotionDockLogoBadge: View {
    var size: CGFloat = 44
    var cornerRadius: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.28, style: .continuous)
                .fill(MotionDockBrand.card)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: MotionDockBrand.accent.opacity(0.18), radius: size * 0.16, y: size * 0.08)

            MotionDockLogoImage()
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(MotionDockBrand.appName)
    }
}
