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
                // -- OUTER GLOW --
                // Idle: dim, Speaking: bright pulse, Listening: mic-reactive
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(glowOpacity(level: level)),
                                glowColor.opacity(glowOpacity(level: level) * 0.3),
                                .clear,
                            ],
                            center: .center,
                            startRadius: size * 0.38,
                            endRadius: size * outerGlowRadius(level: level)
                        )
                    )
                    .frame(width: size * 1.5, height: size * 1.5)
                    .scaleEffect(outerGlowScale(t: t, level: level))

                // -- ORB IMAGE --
                Image("VoiceOrb")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .scaleEffect(orbScale(t: t, level: level))
                    .rotationEffect(.degrees(orbRotation(t: t, level: level)))

                // -- STATE-SPECIFIC OVERLAYS --
                switch state {
                case .idle:
                    idleOverlay(t: t)
                case .listening:
                    listeningOverlay(t: t, level: level)
                case .processing:
                    processingOverlay(t: t)
                case .speaking:
                    speakingOverlay(t: t, level: level)
                }

                // -- SPECULAR GLINT (always present) --
                Circle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .blur(radius: 2)
                    .offset(
                        x: -size * 0.18 + CGFloat(sin(t * 0.3)) * 3,
                        y: -size * 0.3 + CGFloat(cos(t * 0.25)) * 2
                    )
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .animation(.easeInOut(duration: 0.5), value: state)
    }

    // MARK: - Idle: gentle slow breathing, faint shimmer

    @ViewBuilder
    private func idleOverlay(t: Double) -> some View {
        // Very subtle slow shimmer
        Circle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.04), .clear],
                    startPoint: UnitPoint(x: 0.3 + sin(t * 0.3) * 0.2, y: 0.2),
                    endPoint: UnitPoint(x: 0.7 + sin(t * 0.3 + 2) * 0.2, y: 0.8)
                )
            )
            .frame(width: size - 4, height: size - 4)
            .blur(radius: 10)
    }

    // MARK: - Listening: bright mic-reactive pulses, cyan tint

    @ViewBuilder
    private func listeningOverlay(t: Double, level: CGFloat) -> some View {
        // Cyan shimmer that intensifies with voice
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.3, green: 0.75, blue: 1.0).opacity(Double(level) * 0.25),
                        Color(red: 0.2, green: 0.6, blue: 1.0).opacity(Double(level) * 0.15),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.5 + sin(t * 1.5) * 0.1, y: 0.4 + cos(t * 1.2) * 0.1),
                    startRadius: 10,
                    endRadius: size * 0.45
                )
            )
            .frame(width: size - 4, height: size - 4)
            .blur(radius: 6)

        // Pulsing ring that expands with audio
        Circle()
            .strokeBorder(
                Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.15 + Double(level) * 0.3),
                lineWidth: 2
            )
            .frame(width: size - 4, height: size - 4)
            .scaleEffect(1.0 + level * 0.06)

        // Moving light band
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.06 + Double(level) * 0.12),
                        Color(red: 0.5, green: 0.85, blue: 1.0).opacity(0.08 + Double(level) * 0.1),
                        .clear,
                    ],
                    startPoint: UnitPoint(x: sin(t * 1.5) * 0.5 + 0.5, y: 0),
                    endPoint: UnitPoint(x: sin(t * 1.5 + 1.5) * 0.5 + 0.5, y: 1)
                )
            )
            .frame(width: size - 6, height: size - 6)
            .blur(radius: 8)
    }

    // MARK: - Processing: spinning ring, pulsing glow

    @ViewBuilder
    private func processingOverlay(t: Double) -> some View {
        // Spinning gradient ring
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3),
                        .clear,
                        .clear,
                        Color(red: 0.5, green: 0.8, blue: 1.0).opacity(0.2),
                        .clear,
                    ],
                    center: .center,
                    startAngle: .degrees(t * 60),
                    endAngle: .degrees(t * 60 + 360)
                ),
                lineWidth: 3
            )
            .frame(width: size + 6, height: size + 6)

        // Pulsing inner glow
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.1 + sin(t * 2.5) * 0.08),
                        .clear,
                    ],
                    center: .center,
                    startRadius: size * 0.15,
                    endRadius: size * 0.4
                )
            )
            .frame(width: size, height: size)
    }

    // MARK: - Speaking: audio-reactive shimmer, warm glow, edge pulse

    @ViewBuilder
    private func speakingOverlay(t: Double, level: CGFloat) -> some View {
        // Water shimmer that flows with speech
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.05 + Double(level) * 0.15),
                        Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.1 + Double(level) * 0.12),
                        .white.opacity(0.04 + Double(level) * 0.08),
                        .clear,
                    ],
                    startPoint: UnitPoint(
                        x: 0.2 + sin(t * 1.0) * 0.3,
                        y: 0.15 + cos(t * 0.8) * 0.15
                    ),
                    endPoint: UnitPoint(
                        x: 0.8 + sin(t * 1.0 + 2) * 0.3,
                        y: 0.85 + cos(t * 0.8 + 1.5) * 0.15
                    )
                )
            )
            .frame(width: size - 4, height: size - 4)
            .blur(radius: 6)

        // Edge glow ring — rotates and brightens with audio
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Color(red: 0.5, green: 0.8, blue: 1.0).opacity(Double(level) * 0.25),
                        .white.opacity(Double(level) * 0.15),
                        .clear,
                        .clear,
                        Color(red: 0.4, green: 0.7, blue: 1.0).opacity(Double(level) * 0.2),
                    ],
                    center: .center,
                    startAngle: .degrees(t * 20),
                    endAngle: .degrees(t * 20 + 360)
                ),
                lineWidth: 2.5
            )
            .frame(width: size - 1, height: size - 1)

        // Bottom reflection pulse
        Ellipse()
            .fill(Color(red: 0.6, green: 0.85, blue: 1.0).opacity(0.08 + Double(level) * 0.12))
            .frame(width: size * 0.5, height: size * 0.1)
            .offset(y: size * 0.4)
            .blur(radius: 5)
    }

    // MARK: - Orb transforms per state

    private func orbScale(t: Double, level: CGFloat) -> CGFloat {
        switch state {
        case .idle:
            return 1.0 + CGFloat(sin(t * 0.5)) * 0.01
        case .listening:
            return 1.0 + level * 0.05 + CGFloat(sin(t * 1.2)) * 0.01
        case .processing:
            return 1.0 + CGFloat(sin(t * 2.0)) * 0.02
        case .speaking:
            return 1.0 + level * 0.04 + CGFloat(sin(t * 0.8)) * 0.01
        }
    }

    private func orbRotation(t: Double, level: CGFloat) -> Double {
        switch state {
        case .idle:
            return sin(t * 0.2) * 0.5
        case .listening:
            return sin(t * 0.8) * (1.0 + Double(level) * 4.0)
        case .processing:
            return sin(t * 1.5) * 1.5
        case .speaking:
            return sin(t * 0.5) * (0.5 + Double(level) * 3.0)
        }
    }

    // MARK: - Glow per state

    private var glowColor: Color {
        switch state {
        case .idle: Color(red: 0.4, green: 0.65, blue: 1.0)
        case .listening: Color(red: 0.3, green: 0.75, blue: 1.0)
        case .processing: Color(red: 0.35, green: 0.6, blue: 0.95)
        case .speaking: Color(red: 0.4, green: 0.7, blue: 1.0)
        }
    }

    private func glowOpacity(level: CGFloat) -> Double {
        switch state {
        case .idle: 0.06
        case .listening: 0.1 + Double(level) * 0.25
        case .processing: 0.08 + sin(Date().timeIntervalSinceReferenceDate * 2) * 0.05
        case .speaking: 0.08 + Double(level) * 0.3
        }
    }

    private func outerGlowRadius(level: CGFloat) -> CGFloat {
        switch state {
        case .idle: 0.6
        case .listening: 0.65 + level * 0.1
        case .processing: 0.65
        case .speaking: 0.65 + level * 0.12
        }
    }

    private func outerGlowScale(t: Double, level: CGFloat) -> CGFloat {
        switch state {
        case .idle:
            return 1.0 + CGFloat(sin(t * 0.4)) * 0.02
        case .listening:
            return 1.0 + level * 0.1 + CGFloat(sin(t * 1.0)) * 0.02
        case .processing:
            return 1.0 + CGFloat(sin(t * 1.5)) * 0.04
        case .speaking:
            return 1.0 + level * 0.12 + CGFloat(sin(t * 0.7)) * 0.02
        }
    }
}

#Preview("Idle") {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .idle, audioLevel: 0)
    }
}
#Preview("Listening") {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .listening, audioLevel: 0.5)
    }
}
#Preview("Processing") {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .processing, audioLevel: 0)
    }
}
#Preview("Speaking") {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .speaking, audioLevel: 0.6)
    }
}
#endif
