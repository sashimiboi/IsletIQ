#if os(iOS)
import SwiftUI

enum VoiceState: Equatable {
    case idle
    case listening
    case processing
    case speaking
}

struct VoiceOrbView: View {
    let state: VoiceState
    let audioLevel: Float

    private let size: CGFloat = 180

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(audioLevel)

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let r = size / 2

                // 1. Clip everything to sphere
                let sphereRect = CGRect(x: center.x - r, y: center.y - r, width: size, height: size)
                let spherePath = Circle().path(in: sphereRect)

                // 2. Draw fluid inside sphere
                context.drawLayer { fluidCtx in
                    fluidCtx.clip(to: spherePath)

                    // Fluid fill — gradient from dark blue bottom to cyan top
                    let fluidTop = center.y - r * fluidLevel(t: t, level: level)
                    let fluidRect = CGRect(x: center.x - r, y: fluidTop, width: size, height: center.y + r - fluidTop)

                    // Wave-distorted top edge of fluid
                    var fluidPath = Path()
                    fluidPath.move(to: CGPoint(x: center.x - r, y: center.y + r))
                    fluidPath.addLine(to: CGPoint(x: center.x + r, y: center.y + r))
                    fluidPath.addLine(to: CGPoint(x: center.x + r, y: fluidTop))

                    // Wavy top edge
                    let steps = 40
                    for i in stride(from: steps, through: 0, by: -1) {
                        let frac = CGFloat(i) / CGFloat(steps)
                        let x = center.x - r + size * frac
                        let wave1 = sin(Double(frac) * 6.0 + t * fluidSpeed * 2.0) * Double(r) * 0.04 * (1.0 + Double(level) * 2.0)
                        let wave2 = sin(Double(frac) * 3.5 + t * fluidSpeed * 1.3 + 1.0) * Double(r) * 0.03
                        let y = fluidTop + wave1 + wave2
                        fluidPath.addLine(to: CGPoint(x: x, y: y))
                    }
                    fluidPath.closeSubpath()

                    // Gradient fill
                    fluidCtx.fill(fluidPath, with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.0, green: 0.05, blue: 0.3),  // deep navy bottom
                            Color(red: 0.0, green: 0.15, blue: 0.55), // dark blue
                            Color(red: 0.0, green: 0.35, blue: 0.75), // mid blue
                            Color(red: 0.1, green: 0.55, blue: 0.9),  // blue
                            Color(red: 0.3, green: 0.7, blue: 1.0),   // cyan at top
                        ]),
                        startPoint: CGPoint(x: center.x, y: center.y + r),
                        endPoint: CGPoint(x: center.x, y: fluidTop)
                    ))

                    // Horizontal ripple lines through the fluid
                    let lineSpacing: CGFloat = 5
                    let lineCount = Int((center.y + r - fluidTop) / lineSpacing)
                    for i in 0..<lineCount {
                        let baseY = fluidTop + CGFloat(i) * lineSpacing + lineSpacing / 2
                        let waveOffset = sin(Double(i) * 0.3 + t * fluidSpeed * 1.5) * Double(r) * 0.02
                        let lineY = baseY + waveOffset

                        // Fade lines: stronger in middle, fade at edges
                        let depth = (lineY - fluidTop) / (center.y + r - fluidTop)
                        let alpha = 0.06 + depth * 0.08

                        var linePath = Path()
                        // Clip line to sphere width at this y position
                        let dy = lineY - center.y
                        let halfWidth = sqrt(max(0, r * r - dy * dy))
                        linePath.move(to: CGPoint(x: center.x - halfWidth + 4, y: lineY))
                        linePath.addLine(to: CGPoint(x: center.x + halfWidth - 4, y: lineY))

                        fluidCtx.stroke(linePath, with: .color(.white.opacity(alpha)), lineWidth: 0.8)
                    }

                    // Subtle bright area near fluid surface
                    let surfaceGlow = CGRect(x: center.x - r * 0.6, y: fluidTop - r * 0.05, width: r * 1.2, height: r * 0.2)
                    fluidCtx.fill(Ellipse().path(in: surfaceGlow), with: .linearGradient(
                        Gradient(colors: [Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.25), .clear]),
                        startPoint: CGPoint(x: surfaceGlow.midX, y: surfaceGlow.minY),
                        endPoint: CGPoint(x: surfaceGlow.midX, y: surfaceGlow.maxY)
                    ))
                }

                // 3. Glass sphere edge
                context.stroke(spherePath, with: .linearGradient(
                    Gradient(colors: [
                        .white.opacity(0.6),
                        Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.35),
                        Color(red: 0.75, green: 0.8, blue: 0.95).opacity(0.2),
                        .white.opacity(0.3),
                    ]),
                    startPoint: CGPoint(x: center.x - r, y: center.y - r),
                    endPoint: CGPoint(x: center.x + r, y: center.y + r)
                ), lineWidth: 1.5)

                // 4. Specular highlight top-left
                let specRect = CGRect(x: center.x - r * 0.4, y: center.y - r * 0.85, width: r * 0.7, height: r * 0.35)
                context.fill(Ellipse().path(in: specRect), with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                    startPoint: CGPoint(x: specRect.midX, y: specRect.minY),
                    endPoint: CGPoint(x: specRect.midX, y: specRect.maxY)
                ))

                // Small bright dot
                let dotRect = CGRect(x: center.x - r * 0.35, y: center.y - r * 0.7, width: r * 0.1, height: r * 0.1)
                context.fill(Circle().path(in: dotRect), with: .color(.white.opacity(0.4)))

                // 5. Bottom reflection
                let bottomRef = CGRect(x: center.x - r * 0.3, y: center.y + r * 0.7, width: r * 0.6, height: r * 0.12)
                context.fill(Ellipse().path(in: bottomRef), with: .color(Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.15)))
            }
            .frame(width: size + 10, height: size + 10)
        }
    }

    // MARK: - Fluid Level (how full the sphere is)

    private func fluidLevel(t: Double, level: CGFloat) -> CGFloat {
        // 0 = empty, 1 = full. Base ~0.65 with breathing + audio
        let base: CGFloat = switch state {
        case .idle: 0.55
        case .listening: 0.60
        case .processing: 0.65
        case .speaking: 0.60
        }
        let breath = CGFloat(sin(t * fluidSpeed * 0.6)) * 0.03
        let audio = level * 0.08
        return base + breath + audio
    }

    private var fluidSpeed: Double {
        switch state {
        case .idle: 0.5
        case .listening: 1.2
        case .processing: 1.8
        case .speaking: 1.0
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .listening, audioLevel: 0.3)
    }
}
#endif
