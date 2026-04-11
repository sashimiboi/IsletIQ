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

    private let size: CGFloat = 175

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(audioLevel)

            ZStack {
                // Frosted white marble base
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.92, green: 0.94, blue: 0.97),
                                Color(red: 0.88, green: 0.91, blue: 0.96),
                                Color(red: 0.82, green: 0.86, blue: 0.93),
                                Color(red: 0.78, green: 0.83, blue: 0.92),
                            ],
                            center: .center,
                            startRadius: size * 0.1,
                            endRadius: size * 0.52
                        )
                    )
                    .frame(width: size, height: size)

                // Blue pigment mass — center/bottom concentrated
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let r = size / 2

                    // Clip to sphere
                    let sphereRect = CGRect(x: center.x - r, y: center.y - r, width: size, height: size)
                    context.clipToLayer { c in
                        c.fill(Circle().path(in: sphereRect), with: .color(.white))
                    }

                    // Main blue mass — sloshing with audio
                    let sway = sin(t * fluidSpeed) * Double(r) * 0.06 * (1.0 + Double(level) * 1.5)
                    let bob = cos(t * fluidSpeed * 0.7) * Double(r) * 0.04 * (1.0 + Double(level))
                    let blueCenter = CGPoint(x: center.x - r * 0.05 + sway, y: center.y + r * 0.1 + bob)
                    let blueW = r * (1.3 + level * 0.15)
                    let blueH = r * (1.4 + level * 0.1)
                    let blueRect = CGRect(x: blueCenter.x - blueW / 2, y: blueCenter.y - blueH / 2, width: blueW, height: blueH)

                    context.drawLayer { blueCtx in
                        blueCtx.addFilter(.blur(radius: 18))

                        // Deep navy core
                        let coreRect = CGRect(x: blueCenter.x - blueW * 0.35, y: blueCenter.y - blueH * 0.2, width: blueW * 0.7, height: blueH * 0.6)
                        blueCtx.fill(Ellipse().path(in: coreRect), with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 0.0, green: 0.04, blue: 0.25),
                                Color(red: 0.0, green: 0.1, blue: 0.45),
                                Color(red: 0.0, green: 0.1, blue: 0.45).opacity(0),
                            ]),
                            center: CGPoint(x: coreRect.midX, y: coreRect.midY + coreRect.height * 0.15),
                            startRadius: 5,
                            endRadius: coreRect.width * 0.55
                        ))

                        // Mid blue spread
                        blueCtx.fill(Ellipse().path(in: blueRect), with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 0.0, green: 0.25, blue: 0.7).opacity(0.9),
                                Color(red: 0.0, green: 0.35, blue: 0.8).opacity(0.6),
                                Color(red: 0.1, green: 0.5, blue: 0.9).opacity(0.3),
                                .clear,
                            ]),
                            center: blueCenter,
                            startRadius: 10,
                            endRadius: blueW * 0.5
                        ))

                        // Cyan upper highlight
                        let cyanRect = CGRect(x: center.x - r * 0.4, y: center.y - r * 0.35, width: r * 0.8, height: r * 0.5)
                        blueCtx.fill(Ellipse().path(in: cyanRect), with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 0.2, green: 0.65, blue: 1.0).opacity(0.7),
                                Color(red: 0.3, green: 0.7, blue: 1.0).opacity(0.3),
                                .clear,
                            ]),
                            center: CGPoint(x: cyanRect.midX, y: cyanRect.midY),
                            startRadius: 5,
                            endRadius: cyanRect.width * 0.5
                        ))
                    }

                    // Horizontal curved ripple lines through the blue area
                    context.drawLayer { lineCtx in
                        lineCtx.clip(to: Circle().path(in: sphereRect))
                        let lineCount = 25
                        let startY = center.y - r * 0.4
                        let endY = center.y + r * 0.55
                        let range = endY - startY

                        for i in 0..<lineCount {
                            let frac = CGFloat(i) / CGFloat(lineCount)
                            let baseY = startY + range * frac

                            // Curve the lines
                            let wave = sin(Double(frac) * 3.0 + t * fluidSpeed * 1.2) * Double(r) * 0.02
                            let y = baseY + wave

                            let dy = y - center.y
                            let hw = sqrt(max(0, r * r - dy * dy))
                            guard hw > 15 else { continue }

                            // Lines stronger in center, fade at edges of blue area
                            let distFromCenter = abs(frac - 0.45) / 0.5
                            let alpha = max(0, 0.12 - distFromCenter * 0.1)
                            guard alpha > 0.01 else { continue }

                            var line = Path()
                            // Curved line
                            let curveAmt = sin(Double(i) * 0.5 + t * fluidSpeed * 0.8) * Double(hw) * 0.06
                            line.move(to: CGPoint(x: center.x - hw * 0.7, y: y))
                            line.addQuadCurve(
                                to: CGPoint(x: center.x + hw * 0.7, y: y),
                                control: CGPoint(x: center.x, y: y + curveAmt)
                            )
                            lineCtx.stroke(line, with: .color(.white.opacity(alpha)), lineWidth: 0.7)
                        }
                    }

                    // Dark caustic spot at bottom
                    let causticRect = CGRect(x: center.x - r * 0.2, y: center.y + r * 0.55, width: r * 0.4, height: r * 0.2)
                    context.drawLayer { c in
                        c.addFilter(.blur(radius: 12))
                        c.fill(Ellipse().path(in: causticRect), with: .radialGradient(
                            Gradient(colors: [Color(red: 0.15, green: 0.1, blue: 0.25).opacity(0.4), .clear]),
                            center: CGPoint(x: causticRect.midX, y: causticRect.midY),
                            startRadius: 2,
                            endRadius: causticRect.width * 0.5
                        ))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())

                // Glass edge — thin translucent ring
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color(red: 0.75, green: 0.85, blue: 1.0).opacity(0.3),
                                Color.white.opacity(0.15),
                                Color(red: 0.8, green: 0.88, blue: 0.98).opacity(0.25),
                                Color.white.opacity(0.45),
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: size, height: size)

                // Specular highlight — top
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.6), .white.opacity(0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.6, height: size * 0.3)
                    .offset(x: -size * 0.05, y: -size * 0.22)
                    .blur(radius: 6)

                // Bright spot
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .offset(x: -size * 0.18, y: -size * 0.32)
                    .blur(radius: 1.5)
            }
        }
        .frame(width: size + 10, height: size + 10)
    }

    private var fluidSpeed: Double {
        switch state {
        case .idle: 0.4
        case .listening: 1.0
        case .processing: 1.6
        case .speaking: 0.8
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .idle, audioLevel: 0.0)
    }
}
#endif
