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

    private let baseSize: CGFloat = 100

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(audioLevel)

            ZStack {
                // Soft outer halo
                Circle()
                    .fill(haloGradient)
                    .frame(width: baseSize + 90, height: baseSize + 90)
                    .scaleEffect(outerScale(t: t, level: level, phase: 1.5))
                    .opacity(state == .idle ? 0.3 : 0.5)
                    .blur(radius: 40)

                // Mid glow ring
                Circle()
                    .fill(midGradient)
                    .frame(width: baseSize + 55, height: baseSize + 55)
                    .scaleEffect(outerScale(t: t, level: level, phase: 1.0))
                    .opacity(0.4)
                    .blur(radius: 25)

                // Inner glow
                Circle()
                    .fill(innerGradient)
                    .frame(width: baseSize + 25, height: baseSize + 25)
                    .scaleEffect(coreScale(t: t, level: level) * 1.05)
                    .opacity(0.5)
                    .blur(radius: 14)

                // Core sphere
                Circle()
                    .fill(coreGradient)
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(coreScale(t: t, level: level))
                    .shadow(color: shadowColor.opacity(0.25), radius: 24, y: 4)

                // Specular highlight
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: baseSize * 0.55, height: baseSize * 0.35)
                    .offset(y: -baseSize * 0.15)
                    .scaleEffect(coreScale(t: t, level: level))
                    .blur(radius: 4)
            }
            .rotationEffect(.degrees(state == .processing ? t.truncatingRemainder(dividingBy: 12) * 30 : 0))
        }
        .animation(.easeInOut(duration: 0.4), value: state)
    }

    // MARK: - Scale

    private func coreScale(t: Double, level: CGFloat) -> CGFloat {
        let breath = sin(t * breathSpeed) * breathAmp
        let audio = level * audioAmp
        return 1.0 + breath + audio
    }

    private func outerScale(t: Double, level: CGFloat, phase: Double) -> CGFloat {
        let breath = sin(t * breathSpeed + phase) * breathAmp * 1.6
        let audio = level * audioAmp * 2.0
        return 1.0 + breath + audio
    }

    // MARK: - State Parameters

    private var breathSpeed: Double {
        switch state {
        case .idle: 1.0
        case .listening: 1.8
        case .processing: 2.5
        case .speaking: 1.8
        }
    }

    private var breathAmp: CGFloat {
        switch state {
        case .idle: 0.025
        case .listening: 0.015
        case .processing: 0.04
        case .speaking: 0.015
        }
    }

    private var audioAmp: CGFloat {
        switch state {
        case .idle: 0.0
        case .listening: 0.12
        case .processing: 0.0
        case .speaking: 0.10
        }
    }

    // MARK: - Colors

    // Deep blue core: brand primary to accent
    private var coreGradient: RadialGradient {
        let center: Color = {
            switch state {
            case .idle: return Color(red: 0.2, green: 0.45, blue: 0.85)     // soft blue
            case .listening: return Color(red: 0.25, green: 0.55, blue: 0.95) // brighter blue
            case .processing: return Color(red: 0.15, green: 0.35, blue: 0.75) // deeper
            case .speaking: return Color(red: 0.3, green: 0.6, blue: 0.95)   // vibrant
            }
        }()
        return RadialGradient(
            colors: [center, Theme.primary, Theme.primaryDark],
            center: .center,
            startRadius: 8,
            endRadius: baseSize * 0.55
        )
    }

    private var innerGradient: RadialGradient {
        RadialGradient(
            colors: [
                state == .speaking ? Theme.accent.opacity(0.6) : Theme.primary.opacity(0.5),
                Theme.primary.opacity(0),
            ],
            center: .center,
            startRadius: 10,
            endRadius: baseSize * 0.7
        )
    }

    private var midGradient: RadialGradient {
        RadialGradient(
            colors: [Theme.primary.opacity(0.3), Theme.primary.opacity(0)],
            center: .center,
            startRadius: 15,
            endRadius: baseSize * 0.9
        )
    }

    private var haloGradient: RadialGradient {
        let color = state == .listening || state == .speaking ? Theme.accent : Theme.primary
        return RadialGradient(
            colors: [color.opacity(0.25), color.opacity(0)],
            center: .center,
            startRadius: 20,
            endRadius: baseSize * 1.1
        )
    }

    private var shadowColor: Color {
        Theme.primary
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack(spacing: 40) {
            VoiceOrbView(state: .listening, audioLevel: 0.5)
            Text("Listening...")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
#endif
