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

            ZStack {
                // Outer glow — pulses with audio
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.15 + Double(level) * 0.2),
                                Color(red: 0.2, green: 0.5, blue: 0.95).opacity(0.05),
                                .clear,
                            ],
                            center: .center,
                            startRadius: size * 0.4,
                            endRadius: size * 0.7
                        )
                    )
                    .frame(width: size * 1.4, height: size * 1.4)
                    .scaleEffect(1.0 + CGFloat(sin(t * speed * 0.8)) * 0.03 + level * 0.08)

                // Base orb image — slight scale breathing
                Image("VoiceOrb")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .scaleEffect(1.0 + CGFloat(sin(t * speed * 0.6)) * 0.015 + level * 0.04)
                    .rotationEffect(.degrees(sin(t * speed * 0.3) * 2.0 * (1.0 + Double(level) * 3.0)))

                // Water shimmer overlay — moves across the orb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.08 + Double(level) * 0.1),
                                Color(red: 0.5, green: 0.8, blue: 1.0).opacity(0.12 + Double(level) * 0.08),
                                .white.opacity(0.05),
                                .clear,
                            ],
                            startPoint: shimmerStart(t: t),
                            endPoint: shimmerEnd(t: t)
                        )
                    )
                    .frame(width: size - 4, height: size - 4)
                    .blur(radius: 8)

                // Secondary shimmer — slower, different angle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.06),
                                .clear,
                            ],
                            startPoint: shimmerStart2(t: t),
                            endPoint: shimmerEnd2(t: t)
                        )
                    )
                    .frame(width: size - 8, height: size - 8)
                    .blur(radius: 12)

                // Specular glint — follows a subtle path
                Circle()
                    .fill(.white.opacity(0.3 + Double(level) * 0.15))
                    .frame(width: 8, height: 8)
                    .blur(radius: 3)
                    .offset(
                        x: -size * 0.18 + CGFloat(sin(t * 0.4)) * 5,
                        y: -size * 0.3 + CGFloat(cos(t * 0.3)) * 3
                    )

                // Edge glow ring — brightens with audio
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color(red: 0.5, green: 0.8, blue: 1.0).opacity(0.05 + Double(level) * 0.15),
                                .white.opacity(0.1 + Double(level) * 0.1),
                                Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.05),
                                .clear,
                                Color(red: 0.6, green: 0.85, blue: 1.0).opacity(0.08 + Double(level) * 0.1),
                            ],
                            center: .center,
                            startAngle: .degrees(t * speed * 15),
                            endAngle: .degrees(t * speed * 15 + 360)
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: size - 2, height: size - 2)
            }
        }
        .frame(width: size * 1.4, height: size * 1.4)
    }

    // MARK: - Shimmer animation points

    private func shimmerStart(t: Double) -> UnitPoint {
        let x = 0.3 + sin(t * speed * 0.5) * 0.3
        let y = 0.2 + cos(t * speed * 0.4) * 0.2
        return UnitPoint(x: x, y: y)
    }

    private func shimmerEnd(t: Double) -> UnitPoint {
        let x = 0.7 + sin(t * speed * 0.5 + 2.0) * 0.3
        let y = 0.8 + cos(t * speed * 0.4 + 1.5) * 0.2
        return UnitPoint(x: x, y: y)
    }

    private func shimmerStart2(t: Double) -> UnitPoint {
        let x = 0.6 + sin(t * speed * 0.3 + 1.0) * 0.3
        let y = 0.3 + cos(t * speed * 0.25) * 0.2
        return UnitPoint(x: x, y: y)
    }

    private func shimmerEnd2(t: Double) -> UnitPoint {
        let x = 0.2 + sin(t * speed * 0.3 + 3.0) * 0.3
        let y = 0.7 + cos(t * speed * 0.25 + 2.0) * 0.2
        return UnitPoint(x: x, y: y)
    }

    private var speed: Double {
        switch state {
        case .idle: 0.6
        case .listening: 1.5
        case .processing: 2.0
        case .speaking: 1.2
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .speaking, audioLevel: 0.4)
    }
}
#endif
