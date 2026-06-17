#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SRC_DIR="Sources/MovingWallpaperMac"
RESOURCE_ASSETS="$SRC_DIR/Resources/Assets.xcassets"
REQUESTED_ASSETS="Assets.xcassets"
BRAND_SRC_DIR="assets/brand"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

write_contents_json() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' > "$path"
}

write_imageset_json() {
  local path="$1"
  local filename="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "images" : [
    {
      "filename" : "$filename",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

copy_if_possible() {
  local source="$1"
  local destination="$2"
  if [[ -n "$source" && -f "$source" ]]; then
    cp "$source" "$destination"
    return 0
  fi
  return 1
}

find_logo_asset() {
  if [[ -f "$BRAND_SRC_DIR/motiondock-logo.png" ]]; then
    printf '%s\n' "$BRAND_SRC_DIR/motiondock-logo.png"
  elif [[ -f "motiondock logo.png" ]]; then
    printf '%s\n' "motiondock logo.png"
  elif [[ -f "$RESOURCE_ASSETS/Brand/MotionDockLogo.imageset/motiondock-logo-mark-placeholder@2x.png" ]]; then
    printf '%s\n' "$RESOURCE_ASSETS/Brand/MotionDockLogo.imageset/motiondock-logo-mark-placeholder@2x.png"
  else
    printf '\n'
  fi
}

find_icon_asset() {
  if [[ -f "$BRAND_SRC_DIR/motiondock-app-icon.png" ]]; then
    printf '%s\n' "$BRAND_SRC_DIR/motiondock-app-icon.png"
  elif [[ -f "motiondock logo.png" ]]; then
    printf '%s\n' "motiondock logo.png"
  elif [[ -f "$RESOURCE_ASSETS/AppIcon.appiconset/icon_512x512@2x.png" ]]; then
    printf '%s\n' "$RESOURCE_ASSETS/AppIcon.appiconset/icon_512x512@2x.png"
  else
    printf '\n'
  fi
}

create_asset_catalogs() {
  local logo_source icon_source
  logo_source="$(find_logo_asset)"
  icon_source="$(find_icon_asset)"

  for catalog in "$REQUESTED_ASSETS" "$RESOURCE_ASSETS"; do
    mkdir -p "$catalog/Brand" "$catalog/MotionDockLogo.imageset" "$catalog/MotionDockAppIcon.imageset"
    mkdir -p "$catalog/Brand/MotionDockLogo.imageset"
    write_contents_json "$catalog/Contents.json"
    write_contents_json "$catalog/Brand/Contents.json"

    write_imageset_json "$catalog/MotionDockLogo.imageset/Contents.json" "motiondock-logo.png"
    write_imageset_json "$catalog/Brand/MotionDockLogo.imageset/Contents.json" "motiondock-logo.png"
    write_imageset_json "$catalog/MotionDockAppIcon.imageset/Contents.json" "motiondock-app-icon.png"

    if copy_if_possible "$logo_source" "$catalog/MotionDockLogo.imageset/motiondock-logo.png"; then
      cp "$catalog/MotionDockLogo.imageset/motiondock-logo.png" "$catalog/Brand/MotionDockLogo.imageset/motiondock-logo.png"
      cp "$catalog/MotionDockLogo.imageset/motiondock-logo.png" "$catalog/Brand/MotionDockLogo.imageset/motiondock-logo-mark-placeholder.png"
      cp "$catalog/MotionDockLogo.imageset/motiondock-logo.png" "$catalog/Brand/MotionDockLogo.imageset/motiondock-logo-mark-placeholder@2x.png"
    else
      echo "No logo asset found. Add assets/brand/motiondock-logo.png to replace placeholders." >&2
    fi

    if ! copy_if_possible "$icon_source" "$catalog/MotionDockAppIcon.imageset/motiondock-app-icon.png"; then
      echo "No app icon asset found. Add assets/brand/motiondock-app-icon.png to replace placeholders." >&2
    fi
  done
}

write_theme_file() {
  cat > "$SRC_DIR/MotionDockTheme.swift" <<'SWIFT'
import SwiftUI

enum MotionDockTheme {
    static let background = Color(hex: 0x101113)
    static let surface = Color(hex: 0x15161A)
    static let secondarySurface = surface
    static let card = Color(hex: 0x1C1D21)
    static let border = Color.white.opacity(0.08)
    static let accent = Color(hex: 0x0A84FF)
    static let cyan = Color(hex: 0x30D5FF)
    static let cyanHighlight = cyan
    static let success = Color(hex: 0x30D158)
    static let secondaryText = Color.white.opacity(0.56)
    static let mutedText = Color.white.opacity(0.36)
    static let cornerRadius: CGFloat = 18
    static let radius = cornerRadius
    static let animation = Animation.easeInOut(duration: 0.18)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
SWIFT
}

write_liquid_components_file() {
  cat > "$SRC_DIR/MotionDockLiquidReflectionComponents.swift" <<'SWIFT'
import SwiftUI

struct MotionDockLogoView: View {
    var size: CGFloat = 44
    var cornerRadius: CGFloat? = nil
    var showsReflection = true

    var body: some View {
        let resolvedRadius = cornerRadius ?? size * 0.28

        ZStack {
            RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MotionDockTheme.card,
                            MotionDockTheme.surface.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: MotionDockTheme.accent.opacity(0.18), radius: size * 0.16, y: size * 0.08)

            MotionDockLogoImage()
                .padding(size * 0.14)

            if showsReflection {
                LiquidReflectionView(lineCount: 4, amplitude: size * 0.035, intensity: 0.7, animated: false)
                    .frame(height: size * 0.24)
                    .offset(y: size * 0.32)
                    .opacity(0.72)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous))
        .accessibilityLabel(MotionDockBrand.appName)
    }
}

struct LiquidReflectionView: View {
    var lineCount = 5
    var amplitude: CGFloat = 5
    var intensity: Double = 1.0
    var animated = false

    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 30.0 : 1.0)) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else {
                    return
                }

                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                let count = max(lineCount, 1)

                for index in 0..<count {
                    let progress = CGFloat(index) / CGFloat(max(count - 1, 1))
                    let baseY = size.height * (0.34 + progress * 0.46)
                    let localAmplitude = amplitude * (1.0 - progress * 0.42)
                    var path = Path()

                    path.move(to: CGPoint(x: -6, y: baseY))
                    let steps = 36
                    for step in 0...steps {
                        let xProgress = CGFloat(step) / CGFloat(steps)
                        let x = xProgress * (size.width + 12) - 6
                        let phase = xProgress * .pi * 2.0 + CGFloat(time * 0.85) + CGFloat(index) * 0.72
                        let y = baseY + sin(phase) * localAmplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                .clear,
                                MotionDockTheme.accent.opacity(0.18 * intensity),
                                MotionDockTheme.cyan.opacity(0.72 * intensity),
                                MotionDockTheme.accent.opacity(0.24 * intensity),
                                .clear
                            ]),
                            startPoint: CGPoint(x: 0, y: baseY),
                            endPoint: CGPoint(x: size.width, y: baseY)
                        ),
                        lineWidth: 1.0 + progress * 0.55
                    )
                }
            }
        }
    }
}

struct MotionDockAmbientBackground: View {
    var body: some View {
        ZStack {
            MotionDockTheme.background

            LiquidReflectionView(lineCount: 7, amplitude: 18, intensity: 0.42, animated: true)
                .frame(height: 190)
                .blur(radius: 0.2)
                .opacity(0.34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            RadialGradient(
                colors: [
                    MotionDockTheme.accent.opacity(0.12),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 540
            )
            .opacity(0.48)
        }
        .allowsHitTesting(false)
    }
}

struct MotionDockCard<Content: View>: View {
    var isSelected = false
    var isInteractive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        MotionDockTheme.card,
                        MotionDockTheme.card.opacity(0.92),
                        MotionDockTheme.surface.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: MotionDockTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MotionDockTheme.cornerRadius, style: .continuous)
                    .stroke(isSelected ? MotionDockTheme.accent : MotionDockTheme.border, lineWidth: isSelected ? 1.8 : 1)
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    LiquidReflectionView(lineCount: 5, amplitude: 4, intensity: 0.9, animated: true)
                        .frame(height: 26)
                        .padding(.horizontal, 18)
                        .offset(y: 7)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: MotionDockTheme.accent.opacity(isSelected ? 0.16 : 0), radius: 18, y: 8)
            .shadow(color: Color.black.opacity(isInteractive ? 0.34 : 0.18), radius: isInteractive ? 18 : 8, y: isInteractive ? 10 : 4)
    }
}

struct MotionDockPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .foregroundStyle(Color.white.opacity(isDisabled ? 0.42 : 1))
        .background {
            ZStack(alignment: .bottom) {
                MotionDockTheme.accent.opacity(isDisabled ? 0.35 : 1)
                if !isDisabled {
                    LiquidReflectionView(lineCount: 4, amplitude: 3, intensity: 0.72, animated: true)
                        .frame(height: 18)
                        .padding(.horizontal, 18)
                        .offset(y: 4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .clipped()
    }
}

struct MotionDockSidebarItem: View {
    let title: String
    let systemImage: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)

                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : MotionDockTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(isSelected ? 0.16 : 0.06))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.white : MotionDockTheme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MotionDockTheme.accent)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 2)
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    LiquidReflectionView(lineCount: 4, amplitude: 2.8, intensity: 0.86, animated: true)
                        .frame(height: 16)
                        .padding(.horizontal, 34)
                        .offset(y: 6)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

struct MotionDockEmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            MotionDockLogoView(size: 86)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .frame(width: 28, height: 28)
                        .background(MotionDockTheme.accent)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }
                        .offset(x: 5, y: 5)
                }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(MotionDockTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .bottom) {
                MotionDockTheme.card
                LiquidReflectionView(lineCount: 5, amplitude: 7, intensity: 0.44, animated: true)
                    .frame(height: 64)
                    .padding(.horizontal, 34)
                    .opacity(0.72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MotionDockTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MotionDockTheme.cornerRadius, style: .continuous)
                .stroke(MotionDockTheme.border, lineWidth: 1)
        }
        .clipped()
    }
}

struct MotionDockLoadingView: View {
    var compact = false

    var body: some View {
        if compact {
            LiquidReflectionView(lineCount: 4, amplitude: 3, intensity: 0.78, animated: true)
                .frame(width: 42, height: 18)
        } else {
            VStack(spacing: 14) {
                MotionDockLogoView(size: 76)
                LiquidReflectionView(lineCount: 5, amplitude: 7, intensity: 0.85, animated: true)
                    .frame(width: 150, height: 34)
                Text("Loading wallpapers...")
                    .font(.callout)
                    .foregroundStyle(MotionDockTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
SWIFT
}

patch_branding_file() {
  require_file "$SRC_DIR/Branding.swift"
  python3 - <<'PY'
from pathlib import Path

path = Path("Sources/MovingWallpaperMac/Branding.swift")
text = path.read_text()

if "static let appIconAssetName" not in text:
    text = text.replace(
'''    static let logoSubdirectory = "Assets.xcassets/Brand/MotionDockLogo.imageset"
    static let wordmarkSubdirectory = "Assets.xcassets/Brand/MotionDockWordmark.imageset"
    static let appIconSubdirectory = "Assets.xcassets/AppIcon.appiconset"
''',
'''    static let appIconAssetName = "MotionDockAppIcon"
    static let logoSubdirectory = "Assets.xcassets/Brand/MotionDockLogo.imageset"
    static let wordmarkSubdirectory = "Assets.xcassets/Brand/MotionDockWordmark.imageset"
    static let appIconSubdirectory = "Assets.xcassets/AppIcon.appiconset"
'''
    )

old = '''    static func logoImage() -> NSImage? {
        imageResource(
            named: "motiondock-logo-mark-placeholder@2x",
            subdirectory: logoSubdirectory
        )
    }
'''
new = '''    static func logoImage() -> NSImage? {
        if let image = NSImage(named: logoAssetName) {
            return image
        }

        return imageResource(named: "motiondock-logo", subdirectory: logoSubdirectory)
            ?? imageResource(named: "motiondock-logo-mark-placeholder@2x", subdirectory: logoSubdirectory)
    }
'''
text = text.replace(old, new)

old = '''    static func statusBarIcon() -> NSImage? {
        guard let source = imageResource(named: "icon_32x32@2x", subdirectory: appIconSubdirectory) else {
            return NSImage(named: NSImage.applicationIconName)
        }

        let image = source.copy() as? NSImage ?? source
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = appName
        return image
    }
'''
new = '''    static func statusBarIcon() -> NSImage? {
        let source = NSImage(named: appIconAssetName)
            ?? imageResource(named: "motiondock-app-icon", subdirectory: "Assets.xcassets/MotionDockAppIcon.imageset")
            ?? imageResource(named: "icon_32x32@2x", subdirectory: appIconSubdirectory)
            ?? NSImage(named: NSImage.applicationIconName)

        guard let source else {
            return nil
        }

        let image = source.copy() as? NSImage ?? source
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = appName
        return image
    }
'''
text = text.replace(old, new)

old = '''            MotionDockLogoBadge(size: logoSize)
'''
new = '''            MotionDockLogoView(size: logoSize)
'''
text = text.replace(old, new)

path.write_text(text)
PY
}

patch_content_view() {
  require_file "$SRC_DIR/ContentView.swift"
  python3 - <<'PY'
from pathlib import Path

path = Path("Sources/MovingWallpaperMac/ContentView.swift")
text = path.read_text()

theme_marker = "\nprivate enum MotionDockTheme {\n"
if theme_marker in text:
    text = text[:text.index(theme_marker)].rstrip() + "\n"

text = text.replace(
'''        .background(MotionDockTheme.background)
        .foregroundStyle(Color.white.opacity(0.92))
''',
'''        .background {
            MotionDockAmbientBackground()
        }
        .foregroundStyle(Color.white.opacity(0.92))
''',
1
)

text = text.replace(
'''        .background(MotionDockTheme.background)''',
'''        .background {
            MotionDockAmbientBackground()
        }'''
)

text = text.replace("MotionDockLogoBadge(", "MotionDockLogoView(")

sidebar_start = text.find("    private func sidebarButton(_ item: SidebarSection, count: Int? = nil) -> some View {")
if sidebar_start != -1:
    sidebar_end = text.find("\n}\n\nprivate struct WallpaperCard", sidebar_start)
    if sidebar_end == -1:
        raise SystemExit("Could not locate end of sidebarButton block")
    new_sidebar = '''    private func sidebarButton(_ item: SidebarSection, count: Int? = nil) -> some View {
        MotionDockSidebarItem(
            title: item.title,
            systemImage: item.systemImage,
            count: count,
            isSelected: selection == item,
            action: {
                withAnimation(MotionDockTheme.animation) {
                    selection = item
                }
            }
        )
    }
'''
    text = text[:sidebar_start] + new_sidebar + text[sidebar_end:]

card_start = text.find("private struct WallpaperCard: View {")
if card_start != -1:
    card_end = text.find("\nprivate struct InspectorPanel", card_start)
    if card_end == -1:
        raise SystemExit("Could not locate end of WallpaperCard block")
    new_card = '''private struct WallpaperCard: View {
    let item: WallpaperLibraryItem
    @ObservedObject var thumbnailStore: WallpaperThumbnailStore
    let isSelected: Bool
    let isRunning: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            MotionDockCard(isSelected: isSelected, isInteractive: isHovered) {
                VStack(alignment: .leading, spacing: 14) {
                    WallpaperPreview(item: item, thumbnail: thumbnailStore.thumbnail(for: item))
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 6) {
                                MetadataBadge(WallpaperMetadata.fileType(for: item))
                                MetadataBadge(WallpaperMetadata.resolution(for: item))
                            }
                            .padding(12)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button(action: onFavorite) {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isFavorite ? Color.yellow : Color.white.opacity(0.74))
                                    .frame(width: 30, height: 30)
                                    .background(Color.black.opacity(0.22))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                            .opacity(isHovered || isFavorite ? 1 : 0)
                            .animation(MotionDockTheme.animation, value: isHovered)
                        }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.94))
                                .lineLimit(1)

                            Spacer()

                            if isRunning {
                                RunningIndicator()
                            }
                        }

                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(MotionDockTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .scaleEffect(isHovered ? 1.018 : 1)
            .animation(MotionDockTheme.animation, value: isHovered)
            .animation(MotionDockTheme.animation, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            thumbnailStore.requestThumbnail(for: item)
        }
    }
}
'''
    text = text[:card_start] + new_card + text[card_end:]

import_start = text.find("private struct ImportWallpaperControl: View {")
if import_start != -1:
    import_end = text.find("\nprivate struct URLImportSheet", import_start)
    if import_end == -1:
        raise SystemExit("Could not locate end of ImportWallpaperControl block")
    new_import = '''private struct ImportWallpaperControl: View {
    let onImportFiles: () -> Void
    let onImportURL: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MotionDockPrimaryButton(title: "Import Wallpaper", systemImage: "plus", action: onImportFiles)
                .frame(width: 190)

            Button(action: onImportURL) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("URL")
                }
            }
            .buttonStyle(MotionDockSecondaryButtonStyle())
            .frame(width: 72)
        }
    }
}
'''
    text = text[:import_start] + new_import + text[import_end:]

empty_start = text.find("private struct EmptyStateView: View {")
if empty_start != -1:
    empty_end = text.find("\nprivate struct PremiumPanel", empty_start)
    if empty_end == -1:
        raise SystemExit("Could not locate end of EmptyStateView block")
    new_empty = '''private struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        MotionDockEmptyStateView(icon: icon, title: title, message: message)
    }
}
'''
    text = text[:empty_start] + new_empty + text[empty_end:]

premium_start = text.find("private struct PremiumPanel<Content: View>: View {")
if premium_start != -1:
    premium_end = text.find("\nprivate struct LabeledControl", premium_start)
    if premium_end == -1:
        raise SystemExit("Could not locate end of PremiumPanel block")
    new_premium = '''private struct PremiumPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        MotionDockCard {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
'''
    text = text[:premium_start] + new_premium + text[premium_end:]

detail_button_start = text.find("private enum DetailActionButtonStyle {")
if detail_button_start != -1:
    detail_button_end = text.find("\nprivate struct MarketplaceCompactRow", detail_button_start)
    if detail_button_end == -1:
        raise SystemExit("Could not locate end of DetailActionButton block")
    new_detail_button = '''private enum DetailActionButtonStyle {
    case primary
    case secondary
    case destructive
}

private struct DetailActionButton: View {
    let title: String
    let systemImage: String
    var style: DetailActionButtonStyle = .secondary
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16, alignment: .center)
                    .clipped()

                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .clipped()
            }
            .frame(width: MotionDockLayout.inspectorContentWidth, height: 44, alignment: .center)
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .foregroundStyle(foregroundColor)
        .background {
            ZStack(alignment: .bottom) {
                backgroundColor

                if style == .primary && !isDisabled {
                    LiquidReflectionView(lineCount: 4, amplitude: 3, intensity: 0.72, animated: true)
                        .frame(height: 18)
                        .padding(.horizontal, 18)
                        .offset(y: 4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .clipped()
    }

    private var foregroundColor: Color {
        if isDisabled {
            return Color.white.opacity(0.34)
        }

        switch style {
        case .primary:
            return Color.white
        case .secondary:
            return Color.white.opacity(0.88)
        case .destructive:
            return Color.red.opacity(0.92)
        }
    }

    private var backgroundColor: Color {
        if isDisabled {
            return Color.white.opacity(0.04)
        }

        switch style {
        case .primary:
            return MotionDockTheme.accent
        case .secondary:
            return Color.white.opacity(0.07)
        case .destructive:
            return Color.red.opacity(0.08)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return Color.clear
        case .secondary:
            return MotionDockTheme.border
        case .destructive:
            return Color.red.opacity(0.18)
        }
    }
}
'''
    text = text[:detail_button_start] + new_detail_button + text[detail_button_end:]

text = text.replace(
'''                ProgressView()
                    .controlSize(.small)
''',
'''                MotionDockLoadingView(compact: true)
                    .frame(width: 42, height: 22)
'''
)

path.write_text(text)
PY
}

main() {
  create_asset_catalogs
  write_theme_file
  write_liquid_components_file
  patch_branding_file
  patch_content_view

  if [[ -x scripts/build-app.sh ]]; then
    ./scripts/build-app.sh
  else
    swift build
  fi
}

main "$@"
