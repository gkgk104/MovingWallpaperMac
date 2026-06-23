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
        let shape = RoundedRectangle(cornerRadius: MotionDockTheme.cornerRadius, style: .continuous)

        content
            .frame(minWidth: 0, maxWidth: .infinity)
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
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(
                        isSelected ? MotionDockTheme.accent : MotionDockTheme.border,
                        lineWidth: isSelected ? 1.8 : 1
                    )
            }
            .overlay(alignment: .bottom) {
                LiquidReflectionView(
                    lineCount: isSelected ? 5 : 4,
                    amplitude: isSelected ? 4 : 2.4,
                    intensity: isSelected ? 0.9 : 0.28,
                    animated: true
                )
                .frame(height: isSelected ? 26 : 18)
                .padding(.horizontal, isSelected ? 18 : 28)
                .padding(.bottom, isSelected ? 3 : 4)
                .opacity(isSelected ? 1 : 0.52)
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: MotionDockTheme.accent.opacity(isSelected ? 0.16 : 0), radius: 18, y: 8)
            .shadow(color: Color.black.opacity(isInteractive ? 0.34 : 0.18), radius: isInteractive ? 18 : 8, y: isInteractive ? 10 : 4)
            .clipped()
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

    @State private var isHovered = false

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(MotionDockSidebarRowButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .clipped()
    }
}

private struct MotionDockSidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground(isPressed: configuration.isPressed))
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
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(MotionDockTheme.animation, value: configuration.isPressed)
            .animation(MotionDockTheme.animation, value: isHovered)
            .animation(MotionDockTheme.animation, value: isSelected)
            .clipped()
    }

    private func rowBackground(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.14)
        }

        if isSelected {
            return Color.white.opacity(0.10)
        }

        if isHovered {
            return Color.white.opacity(0.06)
        }

        return Color.clear
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
