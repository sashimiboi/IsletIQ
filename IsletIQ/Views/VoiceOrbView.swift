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
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(audioLevel)

            ZStack {
                // Orbital rings (sci-fi)
                orbitalRing(t: t, level: level, tilt: 75, speed: 0.3, radius: size * 0.58, opacity: 0.12)
                orbitalRing(t: t, level: level, tilt: 65, speed: -0.2, radius: size * 0.54, opacity: 0.08)

                // Glass sphere shell
                glassShell

                // Inner fluid layers
                ZStack {
                    fluidBlob(t: t, level: level, phase: 0, color1: Color(red: 0.0, green: 0.08, blue: 0.45), color2: Color(red: 0.0, green: 0.15, blue: 0.6), scaleBase: 0.72, blur: 10)
                    fluidBlob(t: t, level: level, phase: 1.8, color1: Color(red: 0.0, green: 0.25, blue: 0.75), color2: Color(red: 0.05, green: 0.4, blue: 0.85), scaleBase: 0.58, blur: 8)
                    fluidBlob(t: t, level: level, phase: 3.5, color1: Color(red: 0.25, green: 0.65, blue: 1.0), color2: Color(red: 0.45, green: 0.8, blue: 1.0), scaleBase: 0.42, blur: 12)
                    fluidBlob(t: t, level: level, phase: 5.0, color1: .white.opacity(0.35), color2: .white.opacity(0.08), scaleBase: 0.5, blur: 16)

                    // Scan line effect
                    scanLine(t: t)
                }
                .clipShape(Circle())
                .frame(width: size - 6, height: size - 6)

                // Energy pulse ring
                energyPulse(t: t, level: level)

                // Glass reflections
                glassReflections

                // Outer orbital ring (in front)
                orbitalRing(t: t, level: level, tilt: 80, speed: 0.15, radius: size * 0.56, opacity: 0.15)
            }
            .frame(width: size + 40, height: size + 40)
        }
        .animation(.easeInOut(duration: 0.4), value: state)
    }

    // MARK: - Fluid Blob

    @ViewBuilder
    private func fluidBlob(t: Double, level: CGFloat, phase: Double, color1: Color, color2: Color, scaleBase: CGFloat, blur: CGFloat) -> some View {
        let speed = fluidSpeed
        let angle = t * speed * 0.5 + phase
        let dx = sin(angle) * Double(size) * 0.14 * (1.0 + Double(level) * 0.7)
        let dy = cos(angle * 0.7 + phase) * Double(size) * 0.11
        let sx = scaleBase + CGFloat(sin(t * speed * 0.8 + phase)) * 0.07 + level * 0.13
        let sy = scaleBase + CGFloat(cos(t * speed * 0.6 + phase * 1.3)) * 0.05 + level * 0.1

        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color1, color2, color2.opacity(0)],
                    center: UnitPoint(x: 0.4 + sin(t * 0.3 + phase) * 0.12, y: 0.4 + cos(t * 0.2) * 0.08),
                    startRadius: 5,
                    endRadius: size * 0.45
                )
            )
            .frame(width: size * sx, height: size * sy)
            .rotationEffect(.degrees(t * speed * 10 + phase * 40))
            .offset(x: dx, y: dy)
            .blur(radius: blur)
    }

    // MARK: - Scan Line

    @ViewBuilder
    private func scanLine(t: Double) -> some View {
        let y = sin(t * fluidSpeed * 0.8) * Double(size) * 0.4
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color(red: 0.4, green: 0.75, blue: 1.0).opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size, height: 2)
            .blur(radius: 1)
            .offset(y: y)
    }

    // MARK: - Orbital Ring

    @ViewBuilder
    private func orbitalRing(t: Double, level: CGFloat, tilt: Double, speed: Double, radius: CGFloat, opacity: Double) -> some View {
        let rotation = t * speed * 60
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Theme.accent.opacity(0),
                        Theme.accent.opacity(opacity + Double(level) * 0.1),
                        Color(red: 0.3, green: 0.65, blue: 1.0).opacity(opacity * 0.7),
                        Theme.accent.opacity(0),
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                lineWidth: 1.0
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0.3, z: 0))
            .rotationEffect(.degrees(rotation))
    }

    // MARK: - Energy Pulse

    @ViewBuilder
    private func energyPulse(t: Double, level: CGFloat) -> some View {
        let pulseScale = 1.0 + sin(t * 2.5) * 0.03 + Double(level) * 0.08
        Circle()
            .strokeBorder(
                RadialGradient(
                    colors: [Theme.accent.opacity(0.2 + Double(level) * 0.15), Theme.accent.opacity(0)],
                    center: .center,
                    startRadius: size * 0.45,
                    endRadius: size * 0.52
                ),
                lineWidth: 2
            )
            .frame(width: size + 8, height: size + 8)
            .scaleEffect(pulseScale)
    }

    // MARK: - Glass Shell

    private var glassShell: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.5),
                            Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.25),
                            .white.opacity(0.1),
                            Color(red: 0.6, green: 0.8, blue: 1.0).opacity(0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: size, height: size)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .clear,
                            Color(red: 0.85, green: 0.92, blue: 1.0).opacity(0.06),
                            Color(red: 0.75, green: 0.88, blue: 1.0).opacity(0.1),
                        ],
                        center: .center,
                        startRadius: size * 0.2,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)
        }
    }

    // MARK: - Glass Reflections

    private var glassReflections: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0)],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: size * 0.45, height: size * 0.28)
                .offset(x: -size * 0.1, y: -size * 0.22)
                .blur(radius: 5)

            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: size * 0.06, height: size * 0.06)
                .offset(x: -size * 0.22, y: -size * 0.26)
                .blur(radius: 1.5)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(red: 0.7, green: 0.88, blue: 1.0).opacity(0.15)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.6, height: size * 0.15)
                .offset(y: size * 0.38)
                .blur(radius: 3)
        }
    }

    // MARK: - Speed

    private var fluidSpeed: Double {
        switch state {
        case .idle: 0.5
        case .listening: 1.0
        case .processing: 1.6
        case .speaking: 1.2
        }
    }
}

#Preview("Idle") {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .idle, audioLevel: 0)
    }
}

#Preview("Speaking") {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .speaking, audioLevel: 0.5)
    }
}
#endif
