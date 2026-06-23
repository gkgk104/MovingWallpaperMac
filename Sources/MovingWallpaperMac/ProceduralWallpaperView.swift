import SwiftUI

final class MotionWallpaperHostView: NSHostingView<ProceduralWallpaperView>, WallpaperPlaybackControlling {
    private let scene: MotionScene
    private let palette: MotionPalette
    private let performanceProfile: PerformanceProfile
    private var paused = false

    init(scene: MotionScene, palette: MotionPalette, performanceProfile: PerformanceProfile) {
        self.scene = scene
        self.palette = palette
        self.performanceProfile = performanceProfile
        super.init(rootView: ProceduralWallpaperView(
            scene: scene,
            palette: palette,
            performanceProfile: performanceProfile,
            isPaused: false
        ))
    }

    @available(*, unavailable)
    required init(rootView: ProceduralWallpaperView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        rootView = ProceduralWallpaperView(
            scene: scene,
            palette: palette,
            performanceProfile: performanceProfile,
            isPaused: paused
        )
    }

    func setMuted(_ muted: Bool) {}

    func setFillMode(_ fillMode: VideoFillMode) {}

    func recoverAfterSystemTransition(isPaused: Bool) {
        setPaused(isPaused)
        needsDisplay = true
    }
}

struct ProceduralWallpaperView: View {
    let scene: MotionScene
    let palette: MotionPalette
    let performanceProfile: PerformanceProfile
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: performanceProfile.motionFrameInterval, paused: isPaused)) { timeline in
            Canvas { context, size in
                drawBackground(in: &context, size: size, date: timeline.date)

                switch scene {
                case .aurora:
                    drawRibbons(in: &context, size: size, date: timeline.date)
                case .orbit:
                    drawOrbits(in: &context, size: size, date: timeline.date)
                case .nebula:
                    drawNebula(in: &context, size: size, date: timeline.date)
                case .ocean:
                    drawOcean(in: &context, size: size, date: timeline.date)
                case .mountain:
                    drawMountainMist(in: &context, size: size, date: timeline.date)
                case .city:
                    drawCyberCity(in: &context, size: size, date: timeline.date)
                case .mesh:
                    drawMesh(in: &context, size: size, date: timeline.date)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let rect = Path(CGRect(origin: .zero, size: size))
        let background = backgroundColors

        let start = CGPoint(
            x: width * (0.12 + 0.08 * CGFloat(sin(time * 0.07))),
            y: height * 0.08
        )
        let end = CGPoint(
            x: width * (0.84 + 0.08 * CGFloat(cos(time * 0.05))),
            y: height * 0.92
        )

        context.fill(
            rect,
            with: .linearGradient(
                Gradient(colors: [
                    background[0],
                    background[1],
                    background[2],
                    background[3]
                ]),
                startPoint: start,
                endPoint: end
            )
        )
    }

    private func drawRibbons(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let palette = accentColors

        for index in 0..<palette.count {
            var path = Path()
            let baseY = height * (0.34 + CGFloat(index) * 0.12)
            let amplitude = height * (0.045 + CGFloat(index) * 0.006)
            let frequency = 1.7 + Double(index) * 0.32
            let speed = 0.18 + Double(index) * 0.035

            path.move(to: CGPoint(x: 0, y: baseY))

            stride(from: CGFloat(0), through: width, by: 10).forEach { x in
                let normalizedX = Double(x / width)
                let wave = sin(normalizedX * Double.pi * 2 * frequency + time * speed + Double(index))
                let counterWave = cos(normalizedX * Double.pi * 3.4 - time * speed * 0.7)
                let y = baseY + CGFloat(wave + counterWave * 0.42) * amplitude
                path.addLine(to: CGPoint(x: x, y: y))
            }

            context.stroke(
                path,
                with: .color(palette[index]),
                style: StrokeStyle(lineWidth: 54 - CGFloat(index) * 7, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawOrbits(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let center = CGPoint(x: width * 0.5, y: height * 0.52)
        let colors = accentColors

        for index in 0..<8 {
            let radiusX = width * (0.14 + CGFloat(index) * 0.045)
            let radiusY = height * (0.10 + CGFloat(index) * 0.034)
            let angle = time * (0.16 + Double(index) * 0.017)
            let rect = CGRect(
                x: center.x - radiusX,
                y: center.y - radiusY,
                width: radiusX * 2,
                height: radiusY * 2
            )
            let ellipse = Path(ellipseIn: rect)
            context.stroke(
                ellipse,
                with: .color(colors[index % colors.count].opacity(0.18 + Double(index) * 0.025)),
                lineWidth: 2.4
            )

            let node = CGPoint(
                x: center.x + cos(angle) * radiusX,
                y: center.y + sin(angle * 1.12) * radiusY
            )
            let nodeRect = CGRect(x: node.x - 12, y: node.y - 12, width: 24, height: 24)
            context.fill(Path(ellipseIn: nodeRect), with: .color(colors[index % colors.count].opacity(0.62)))
        }
    }

    private func drawNebula(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let colors = accentColors
        let starCount = performanceProfile == .batterySaver ? 44 : 86

        for index in 0..<starCount {
            let seed = Double(index + 1)
            let x = width * unitNoise(seed * 17.2)
            let y = height * unitNoise(seed * 31.7)
            let pulse = 0.42 + 0.34 * sin(time * 0.55 + seed)
            let radius = CGFloat(0.7 + unitNoise(seed * 5.1) * 1.9)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                with: .color(Color.white.opacity(0.20 + pulse * 0.24))
            )
        }

        for index in 0..<6 {
            var path = Path()
            let baseY = height * (0.22 + CGFloat(index) * 0.095)
            let drift = CGFloat(sin(time * (0.18 + Double(index) * 0.04))) * width * 0.05

            path.move(to: CGPoint(x: -width * 0.10 + drift, y: baseY))
            path.addCurve(
                to: CGPoint(x: width * 1.10 + drift * 0.3, y: height * (0.76 - CGFloat(index) * 0.045)),
                control1: CGPoint(x: width * 0.20, y: baseY - height * (0.18 + CGFloat(index) * 0.012)),
                control2: CGPoint(x: width * 0.68, y: height * (0.52 + CGFloat(index) * 0.032))
            )

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        colors[index % colors.count].opacity(0.18),
                        MotionDockTheme.cyan.opacity(0.32),
                        colors[(index + 1) % colors.count].opacity(0.16),
                        .clear
                    ]),
                    startPoint: CGPoint(x: 0, y: baseY),
                    endPoint: CGPoint(x: width, y: baseY)
                ),
                style: StrokeStyle(lineWidth: 42 - CGFloat(index) * 4.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawOcean(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let colors = accentColors
        let horizonY = height * 0.52

        let glowRect = CGRect(x: -width * 0.08, y: horizonY - height * 0.24, width: width * 1.16, height: height * 0.36)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    MotionDockTheme.cyan.opacity(0.26),
                    colors.first?.opacity(0.18) ?? MotionDockTheme.accent.opacity(0.18),
                    .clear
                ]),
                center: CGPoint(x: width * 0.5, y: horizonY),
                startRadius: 0,
                endRadius: width * 0.58
            )
        )

        for index in 0..<7 {
            var path = Path()
            let baseY = horizonY + height * (0.05 + CGFloat(index) * 0.055)
            let amplitude = height * (0.008 + CGFloat(index) * 0.003)
            path.move(to: CGPoint(x: -8, y: baseY))

            for step in 0...50 {
                let xProgress = CGFloat(step) / 50
                let x = xProgress * (width + 16) - 8
                let phase = Double(xProgress) * Double.pi * (2.0 + Double(index) * 0.26) + time * (0.22 + Double(index) * 0.05)
                let y = baseY + CGFloat(sin(phase)) * amplitude
                path.addLine(to: CGPoint(x: x, y: y))
            }

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        colors[index % colors.count].opacity(0.26),
                        MotionDockTheme.cyan.opacity(0.38),
                        .clear
                    ]),
                    startPoint: CGPoint(x: 0, y: baseY),
                    endPoint: CGPoint(x: width, y: baseY)
                ),
                lineWidth: 1.4 + CGFloat(index) * 0.5
            )
        }
    }

    private func drawMountainMist(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let colors = accentColors

        for layer in 0..<3 {
            var mountain = Path()
            let baseY = height * (0.62 + CGFloat(layer) * 0.09)
            mountain.move(to: CGPoint(x: 0, y: height))
            mountain.addLine(to: CGPoint(x: 0, y: baseY))

            for point in 0...7 {
                let progress = CGFloat(point) / 7
                let x = width * progress
                let peak = sin(Double(point) * 1.7 + Double(layer)) * 0.5 + 0.5
                let y = baseY - height * CGFloat(0.14 + peak * (0.16 - Double(layer) * 0.025))
                mountain.addLine(to: CGPoint(x: x, y: y))
            }

            mountain.addLine(to: CGPoint(x: width, y: height))
            mountain.closeSubpath()
            context.fill(
                mountain,
                with: .color(Color.black.opacity(0.25 + Double(layer) * 0.18))
            )
        }

        for index in 0..<7 {
            var mist = Path()
            let baseY = height * (0.34 + CGFloat(index) * 0.07)
            let offset = CGFloat(sin(time * (0.14 + Double(index) * 0.025))) * width * 0.06
            mist.move(to: CGPoint(x: -width * 0.08 + offset, y: baseY))
            mist.addCurve(
                to: CGPoint(x: width * 1.08 + offset * 0.4, y: baseY + height * 0.04),
                control1: CGPoint(x: width * 0.22, y: baseY - height * 0.08),
                control2: CGPoint(x: width * 0.72, y: baseY + height * 0.09)
            )
            context.stroke(
                mist,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        colors[index % colors.count].opacity(0.16),
                        Color.white.opacity(0.12),
                        .clear
                    ]),
                    startPoint: CGPoint(x: 0, y: baseY),
                    endPoint: CGPoint(x: width, y: baseY)
                ),
                style: StrokeStyle(lineWidth: 18 - CGFloat(index) * 1.5, lineCap: .round)
            )
        }
    }

    private func drawCyberCity(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let colors = accentColors
        let skylineBase = height * 0.70
        let buildingCount = performanceProfile == .batterySaver ? 12 : 18

        for index in 0..<buildingCount {
            let progress = CGFloat(index) / CGFloat(max(buildingCount - 1, 1))
            let buildingWidth = width / CGFloat(buildingCount) * 0.72
            let x = width * progress
            let buildingHeight = height * (0.16 + unitNoise(Double(index) * 9.7) * 0.28)
            let rect = CGRect(x: x, y: skylineBase - buildingHeight, width: buildingWidth, height: buildingHeight)
            context.fill(Path(rect), with: .color(Color.black.opacity(0.54)))

            let accent = colors[index % colors.count]
            context.stroke(
                Path(rect),
                with: .color(accent.opacity(0.18 + 0.10 * sin(time * 0.7 + Double(index)))),
                lineWidth: 1.2
            )

            for window in 0..<4 {
                let windowY = rect.minY + CGFloat(window + 1) * rect.height / 5
                let windowRect = CGRect(
                    x: rect.minX + rect.width * 0.18,
                    y: windowY,
                    width: rect.width * 0.58,
                    height: 1.4
                )
                context.fill(
                    Path(windowRect),
                    with: .color(accent.opacity(0.24 + 0.18 * unitNoise(Double(index * 11 + window))))
                )
            }
        }

        for index in 0..<6 {
            var reflection = Path()
            let baseY = skylineBase + height * (0.04 + CGFloat(index) * 0.037)
            reflection.move(to: CGPoint(x: -10, y: baseY))
            for step in 0...44 {
                let xProgress = CGFloat(step) / 44
                let x = xProgress * (width + 20) - 10
                let y = baseY + CGFloat(sin(Double(xProgress) * Double.pi * 4 + time * 0.34 + Double(index))) * height * 0.008
                reflection.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(
                reflection,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        MotionDockTheme.accent.opacity(0.18),
                        MotionDockTheme.cyan.opacity(0.36),
                        .clear
                    ]),
                    startPoint: CGPoint(x: 0, y: baseY),
                    endPoint: CGPoint(x: width, y: baseY)
                ),
                lineWidth: 1.5 + CGFloat(index) * 0.25
            )
        }
    }

    private func drawMesh(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate * performanceProfile.motionSpeedScale
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let colors = accentColors
        let columns = performanceProfile == .batterySaver ? 9 : 15
        let rows = performanceProfile == .batterySaver ? 6 : 10

        for row in 0...rows {
            var path = Path()
            for column in 0...columns {
                let x = width * CGFloat(column) / CGFloat(columns)
                let baseY = height * CGFloat(row) / CGFloat(rows)
                let wave = sin(Double(column) * 0.75 + time * 0.42 + Double(row) * 0.34)
                let y = baseY + CGFloat(wave) * height * 0.018

                if column == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(colors[row % colors.count].opacity(0.23)), lineWidth: 1.4)
        }

        for column in 0...columns {
            var path = Path()
            for row in 0...rows {
                let baseX = width * CGFloat(column) / CGFloat(columns)
                let y = height * CGFloat(row) / CGFloat(rows)
                let wave = cos(Double(row) * 0.65 + time * 0.38 + Double(column) * 0.21)
                let x = baseX + CGFloat(wave) * width * 0.012

                if row == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(colors[column % colors.count].opacity(0.16)), lineWidth: 1.0)
        }
    }

    private func unitNoise(_ seed: Double) -> CGFloat {
        let value = sin(seed * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }

    private var backgroundColors: [Color] {
        switch palette {
        case .aurora:
            return [
                Color(red: 0.03, green: 0.05, blue: 0.08),
                Color(red: 0.07, green: 0.17, blue: 0.20),
                Color(red: 0.24, green: 0.22, blue: 0.18),
                Color(red: 0.04, green: 0.08, blue: 0.11)
            ]
        case .ember:
            return [
                Color(red: 0.08, green: 0.04, blue: 0.04),
                Color(red: 0.22, green: 0.08, blue: 0.06),
                Color(red: 0.30, green: 0.17, blue: 0.08),
                Color(red: 0.04, green: 0.05, blue: 0.05)
            ]
        case .graphite:
            return [
                Color(red: 0.03, green: 0.04, blue: 0.05),
                Color(red: 0.12, green: 0.14, blue: 0.15),
                Color(red: 0.08, green: 0.10, blue: 0.11),
                Color(red: 0.02, green: 0.03, blue: 0.04)
            ]
        case .prism:
            return [
                Color(red: 0.04, green: 0.05, blue: 0.11),
                Color(red: 0.12, green: 0.08, blue: 0.22),
                Color(red: 0.06, green: 0.16, blue: 0.20),
                Color(red: 0.05, green: 0.04, blue: 0.08)
            ]
        }
    }

    private var accentColors: [Color] {
        switch palette {
        case .aurora:
            return [
                Color(red: 0.50, green: 0.86, blue: 0.92, opacity: 0.46),
                Color(red: 0.95, green: 0.55, blue: 0.38, opacity: 0.34),
                Color(red: 0.78, green: 0.86, blue: 0.52, opacity: 0.30),
                Color(red: 0.62, green: 0.66, blue: 0.96, opacity: 0.28)
            ]
        case .ember:
            return [
                Color(red: 0.98, green: 0.36, blue: 0.18, opacity: 0.44),
                Color(red: 0.96, green: 0.70, blue: 0.28, opacity: 0.32),
                Color(red: 0.74, green: 0.16, blue: 0.12, opacity: 0.34),
                Color(red: 0.92, green: 0.50, blue: 0.26, opacity: 0.28)
            ]
        case .graphite:
            return [
                Color(red: 0.72, green: 0.78, blue: 0.80, opacity: 0.28),
                Color(red: 0.38, green: 0.55, blue: 0.58, opacity: 0.22),
                Color(red: 0.82, green: 0.88, blue: 0.72, opacity: 0.20),
                Color(red: 0.52, green: 0.64, blue: 0.82, opacity: 0.18)
            ]
        case .prism:
            return [
                Color(red: 0.42, green: 0.84, blue: 0.92, opacity: 0.38),
                Color(red: 0.82, green: 0.42, blue: 0.94, opacity: 0.30),
                Color(red: 0.92, green: 0.78, blue: 0.34, opacity: 0.28),
                Color(red: 0.48, green: 0.92, blue: 0.60, opacity: 0.25)
            ]
        }
    }
}
