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

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let r = size / 2

                // 1. Draw fluid blobs
                drawFluid(context: &context, center: center, r: r, t: t, level: level)

                // 2. Glass shell ring
                let shellRect = CGRect(x: center.x - r, y: center.y - r, width: size, height: size)
                let shellPath = Circle().path(in: shellRect)
                context.stroke(shellPath, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.5), Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.3), .white.opacity(0.15)]),
                    startPoint: CGPoint(x: center.x - r, y: center.y - r),
                    endPoint: CGPoint(x: center.x + r, y: center.y + r)
                ), lineWidth: 1.5)

                // 3. Specular highlight
                let specRect = CGRect(x: center.x - r * 0.3, y: center.y - r * 0.85, width: r * 0.5, height: r * 0.3)
                context.fill(Ellipse().path(in: specRect), with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.4), .white.opacity(0)]),
                    startPoint: CGPoint(x: specRect.midX, y: specRect.minY),
                    endPoint: CGPoint(x: specRect.midX, y: specRect.maxY)
                ))

            } symbols: {}
                .frame(width: size + 20, height: size + 20)
                .clipShape(Circle().inset(by: -10))
        }
    }

    private func drawFluid(context: inout GraphicsContext, center: CGPoint, r: CGFloat, t: Double, level: CGFloat) {
        let speed = fluidSpeed

        // Clip to sphere
        let clipRect = CGRect(x: center.x - r + 3, y: center.y - r + 3, width: (r - 3) * 2, height: (r - 3) * 2)
        context.clipToLayer { ctx in
            ctx.fill(Circle().path(in: clipRect), with: .color(.white))
        }

        // Blob 1: deep blue, large
        drawBlob(context: &context, center: center, r: r, t: t, level: level,
                 phase: 0, scaleBase: 0.75, blur: 18, speed: speed,
                 color: Color(red: 0.0, green: 0.1, blue: 0.5))

        // Blob 2: mid blue
        drawBlob(context: &context, center: center, r: r, t: t, level: level,
                 phase: 2.0, scaleBase: 0.6, blur: 14, speed: speed,
                 color: Color(red: 0.05, green: 0.3, blue: 0.8))

        // Blob 3: cyan highlight
        drawBlob(context: &context, center: center, r: r, t: t, level: level,
                 phase: 4.0, scaleBase: 0.45, blur: 20, speed: speed,
                 color: Color(red: 0.3, green: 0.65, blue: 1.0).opacity(0.7))
    }

    private func drawBlob(context: inout GraphicsContext, center: CGPoint, r: CGFloat, t: Double, level: CGFloat, phase: Double, scaleBase: CGFloat, blur: CGFloat, speed: Double, color: Color) {
        let angle = t * speed * 0.5 + phase
        let dx = sin(angle) * Double(r) * 0.25 * (1.0 + Double(level) * 0.6)
        let dy = cos(angle * 0.7 + phase) * Double(r) * 0.2
        let s = scaleBase + CGFloat(sin(t * speed * 0.7 + phase)) * 0.06 + level * 0.1

        let blobW = r * 2 * s
        let blobH = r * 2 * s * 0.7
        let blobCenter = CGPoint(x: center.x + dx, y: center.y + dy)
        let blobRect = CGRect(x: blobCenter.x - blobW / 2, y: blobCenter.y - blobH / 2, width: blobW, height: blobH)

        var blobCtx = context
        blobCtx.addFilter(.blur(radius: blur))
        blobCtx.fill(Ellipse().path(in: blobRect), with: .radialGradient(
            Gradient(colors: [color, color.opacity(0)]),
            center: blobCenter,
            startRadius: 5,
            endRadius: blobW * 0.5
        ))
    }

    private var fluidSpeed: Double {
        switch state {
        case .idle: 0.5
        case .listening: 1.0
        case .processing: 1.5
        case .speaking: 1.1
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
