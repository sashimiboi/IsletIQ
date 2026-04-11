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

    private let size: CGFloat = 170

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(audioLevel)

            ZStack {
                // Drop shadow beneath sphere
                Ellipse()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: size * 0.6, height: size * 0.12)
                    .offset(y: size * 0.52)
                    .blur(radius: 10)

                // Glass sphere with fluid
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let r = size / 2
                    let sphereRect = CGRect(x: center.x - r, y: center.y - r, width: size, height: size)
                    let spherePath = Circle().path(in: sphereRect)

                    // -- FLUID --
                    context.drawLayer { ctx in
                        ctx.clip(to: spherePath)

                        let fluidY = center.y - r * fluidLevel(t: t, level: level)

                        // Fluid body with wave top
                        var fluid = Path()
                        fluid.move(to: CGPoint(x: center.x - r, y: center.y + r))
                        fluid.addLine(to: CGPoint(x: center.x + r, y: center.y + r))
                        fluid.addLine(to: CGPoint(x: center.x + r, y: fluidY))
                        let steps = 30
                        for i in stride(from: steps, through: 0, by: -1) {
                            let frac = CGFloat(i) / CGFloat(steps)
                            let x = center.x - r + size * frac
                            let w1 = sin(Double(frac) * 5.0 + t * fluidSpeed * 2.0) * Double(r) * 0.035 * (1.0 + Double(level) * 2.5)
                            let w2 = sin(Double(frac) * 8.0 + t * fluidSpeed * 1.5 + 2.0) * Double(r) * 0.015
                            fluid.addLine(to: CGPoint(x: x, y: fluidY + w1 + w2))
                        }
                        fluid.closeSubpath()

                        ctx.fill(fluid, with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 0.0, green: 0.03, blue: 0.2),
                                Color(red: 0.0, green: 0.1, blue: 0.45),
                                Color(red: 0.0, green: 0.3, blue: 0.7),
                                Color(red: 0.15, green: 0.5, blue: 0.9),
                                Color(red: 0.35, green: 0.7, blue: 1.0),
                            ]),
                            startPoint: CGPoint(x: center.x, y: center.y + r),
                            endPoint: CGPoint(x: center.x, y: fluidY)
                        ))

                        // Ripple lines
                        let spacing: CGFloat = 4.5
                        let count = Int((center.y + r - fluidY) / spacing)
                        for i in 0..<count {
                            let baseY = fluidY + CGFloat(i) * spacing + 3
                            let wave = sin(Double(i) * 0.4 + t * fluidSpeed * 1.2) * Double(r) * 0.015
                            let y = baseY + wave
                            let dy = y - center.y
                            let hw = sqrt(max(0, r * r - dy * dy))
                            guard hw > 5 else { continue }
                            let depth = CGFloat(i) / CGFloat(max(count, 1))
                            let alpha = 0.04 + depth * 0.06

                            var line = Path()
                            line.move(to: CGPoint(x: center.x - hw + 6, y: y))
                            line.addLine(to: CGPoint(x: center.x + hw - 6, y: y))
                            ctx.stroke(line, with: .color(.white.opacity(alpha)), lineWidth: 0.6)
                        }

                        // Bright meniscus at fluid surface
                        let meniscus = CGRect(x: center.x - r * 0.5, y: fluidY - 2, width: r, height: 6)
                        ctx.fill(Ellipse().path(in: meniscus), with: .linearGradient(
                            Gradient(colors: [Color(red: 0.5, green: 0.85, blue: 1.0).opacity(0.3), .clear]),
                            startPoint: CGPoint(x: meniscus.midX, y: meniscus.minY),
                            endPoint: CGPoint(x: meniscus.midX, y: meniscus.maxY)
                        ))
                    }

                    // -- GLASS EDGE --
                    // Thick outer ring for glass depth
                    context.stroke(spherePath, with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.85, green: 0.9, blue: 1.0).opacity(0.7),
                            Color(red: 0.6, green: 0.75, blue: 0.95).opacity(0.3),
                            Color(red: 0.8, green: 0.88, blue: 1.0).opacity(0.15),
                            Color(red: 0.7, green: 0.82, blue: 0.95).opacity(0.5),
                        ]),
                        startPoint: CGPoint(x: center.x - r, y: center.y - r),
                        endPoint: CGPoint(x: center.x + r, y: center.y + r)
                    ), lineWidth: 2.5)

                    // Inner edge highlight
                    let inner = CGRect(x: center.x - r + 3, y: center.y - r + 3, width: size - 6, height: size - 6)
                    context.stroke(Circle().path(in: inner), with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                .frame(width: size, height: size)

                // -- GLASS REFLECTIONS (SwiftUI overlays for quality) --

                // Large specular arc top-left
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.15), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.55, height: size * 0.35)
                    .offset(x: -size * 0.08, y: -size * 0.2)
                    .blur(radius: 3)

                // Small bright dot
                Circle()
                    .fill(.white.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .offset(x: -size * 0.2, y: -size * 0.28)
                    .blur(radius: 1)

                // Edge refraction glow (bottom-right)
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(red: 0.7, green: 0.88, blue: 1.0).opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.5, height: size * 0.12)
                    .offset(x: size * 0.05, y: size * 0.38)
                    .blur(radius: 3)

                // Rim light right edge
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.clear, .clear, .white.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3
                    )
                    .frame(width: size - 2, height: size - 2)
            }
            .frame(width: size + 20, height: size + 30)
        }
    }

    private func fluidLevel(t: Double, level: CGFloat) -> CGFloat {
        let base: CGFloat = switch state {
        case .idle: 0.5
        case .listening: 0.55
        case .processing: 0.6
        case .speaking: 0.55
        }
        let breath = CGFloat(sin(t * fluidSpeed * 0.5)) * 0.025
        let audio = level * 0.06
        return base + breath + audio
    }

    private var fluidSpeed: Double {
        switch state {
        case .idle: 0.6
        case .listening: 1.3
        case .processing: 2.0
        case .speaking: 1.1
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
