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

    private let baseSize: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(audioLevel)

            ZStack {
                // Outer glow ring 2
                Circle()
                    .fill(glowGradient.opacity(0.08))
                    .frame(width: baseSize + 80, height: baseSize + 80)
                    .scaleEffect(outerScale2(t: t, level: level))
                    .blur(radius: 30)

                // Outer glow ring 1
                Circle()
                    .fill(glowGradient.opacity(0.15))
                    .frame(width: baseSize + 50, height: baseSize + 50)
                    .scaleEffect(outerScale1(t: t, level: level))
                    .blur(radius: 20)

                // Inner glow
                Circle()
                    .fill(coreGradient)
                    .frame(width: baseSize + 20, height: baseSize + 20)
                    .scaleEffect(innerScale(t: t, level: level))
                    .blur(radius: 12)
                    .opacity(0.6)

                // Core sphere
                Circle()
                    .fill(coreGradient)
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(coreScale(t: t, level: level))
                    .blur(radius: 4)
                    .shadow(color: glowColor.opacity(0.4), radius: 20)

                // Bright center dot
                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: baseSize * 0.3, height: baseSize * 0.3)
                    .blur(radius: 8)
                    .scaleEffect(coreScale(t: t, level: level))
            }
            .rotationEffect(.degrees(state == .processing ? t.truncatingRemainder(dividingBy: 10) * 36 : 0))
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    // MARK: - Scale Functions

    private func coreScale(t: Double, level: CGFloat) -> CGFloat {
        let breath = sin(t * breathSpeed) * breathAmplitude
        let audio = level * audioAmplitude
        return 1.0 + breath + audio
    }

    private func innerScale(t: Double, level: CGFloat) -> CGFloat {
        let breath = sin(t * breathSpeed + 0.5) * breathAmplitude * 1.2
        let audio = level * audioAmplitude * 1.3
        return 1.0 + breath + audio
    }

    private func outerScale1(t: Double, level: CGFloat) -> CGFloat {
        let breath = sin(t * breathSpeed + 1.0) * breathAmplitude * 1.5
        let audio = level * audioAmplitude * 1.8
        return 1.0 + breath + audio
    }

    private func outerScale2(t: Double, level: CGFloat) -> CGFloat {
        let breath = sin(t * breathSpeed + 1.5) * breathAmplitude * 1.8
        let audio = level * audioAmplitude * 2.2
        return 1.0 + breath + audio
    }

    // MARK: - State-dependent Parameters

    private var breathSpeed: Double {
        switch state {
        case .idle: 1.2
        case .listening: 2.0
        case .processing: 3.0
        case .speaking: 2.0
        }
    }

    private var breathAmplitude: CGFloat {
        switch state {
        case .idle: 0.03
        case .listening: 0.02
        case .processing: 0.05
        case .speaking: 0.02
        }
    }

    private var audioAmplitude: CGFloat {
        switch state {
        case .idle: 0.0
        case .listening: 0.15
        case .processing: 0.0
        case .speaking: 0.12
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle: Theme.primary
        case .listening: Theme.accent
        case .processing: Theme.primary
        case .speaking: Theme.accent
        }
    }

    private var coreGradient: RadialGradient {
        RadialGradient(
            colors: [
                state == .speaking || state == .listening ? Theme.accent : Theme.primary.opacity(0.8),
                Theme.primary,
                Theme.primaryDark,
            ],
            center: .center,
            startRadius: 5,
            endRadius: baseSize * 0.6
        )
    }

    private var glowGradient: RadialGradient {
        RadialGradient(
            colors: [glowColor, glowColor.opacity(0)],
            center: .center,
            startRadius: 10,
            endRadius: baseSize
        )
    }
}

#Preview {
    ZStack {
        Color(red: 0.04, green: 0.05, blue: 0.1).ignoresSafeArea()
        VStack(spacing: 40) {
            VoiceOrbView(state: .listening, audioLevel: 0.5)
            Text("Listening...").foregroundStyle(.white.opacity(0.6))
        }
    }
    .preferredColorScheme(.dark)
}
#endif
