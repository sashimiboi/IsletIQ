#if os(iOS)
import SwiftUI
import MetalKit
import UIKit

enum VoiceState: Equatable {
    case idle
    case listening
    case processing
    case speaking
}

// MARK: - SwiftUI Wrapper

struct VoiceOrbView: View {
    let state: VoiceState
    let audioLevel: Float

    var body: some View {
        OrbMetalView(state: state, audioLevel: audioLevel)
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - UIKit Bridge

struct OrbMetalView: UIViewRepresentable {
    let state: VoiceState
    let audioLevel: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.state = state
        context.coordinator.audioLevel = audioLevel
    }

    func makeCoordinator() -> OrbRenderer {
        OrbRenderer()
    }
}

// MARK: - Uniforms (must match Metal struct layout)

struct OrbUniforms {
    var time: Float = 0        // 0
    var animation: Float = 0   // 4
    var inputVolume: Float = 0 // 8
    var outputVolume: Float = 0 // 12
    var color1: SIMD2<Float> = SIMD2(0.792, 0.863)  // 16
    var color1b: SIMD2<Float> = SIMD2(0.988, 0)     // 24
    var color2: SIMD2<Float> = SIMD2(0.627, 0.725)  // 32
    var color2b: SIMD2<Float> = SIMD2(0.820, 0)     // 40
    var offsets: (Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0) // 48, pad to 80
}

// MARK: - Metal Renderer

class OrbRenderer: NSObject, MTKViewDelegate {
    var state: VoiceState = .idle
    var audioLevel: Float = 0

    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var perlinTexture: MTLTexture?
    private var uniforms = OrbUniforms()
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var curIn: Float = 0
    private var curOut: Float = 0.3
    private var animSpeed: Float = 0.1
    private var commandQueue: MTLCommandQueue?

    override init() {
        super.init()

        // Random offsets
        uniforms.offsets = (
            Float.random(in: 0...(2 * .pi)),
            Float.random(in: 0...(2 * .pi)),
            Float.random(in: 0...(2 * .pi)),
            Float.random(in: 0...(2 * .pi)),
            Float.random(in: 0...(2 * .pi)),
            Float.random(in: 0...(2 * .pi)),
            Float.random(in: 0...(2 * .pi)),
            0 // padding
        )

        // IsletIQ brand: Theme.primary #0033A0, Theme.accent #5CB3CC
        let c1 = SIMD3<Float>(0.36, 0.70, 0.80)  // accent teal #5CB3CC
        let c2 = SIMD3<Float>(0.0, 0.20, 0.63)   // primary blue #0033A0
        uniforms.color1 = SIMD2(c1.x, c1.y)
        uniforms.color1b = SIMD2(c1.z, 0)
        uniforms.color2 = SIMD2(c2.x, c2.y)
        uniforms.color2b = SIMD2(c2.z, 0)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let device = view.device else { return }

        // Lazy init
        if pipelineState == nil {
            setup(device: device, view: view)
        }

        guard let pipeline = pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let queue = commandQueue
        else { return }

        // Update uniforms
        let now = CACurrentMediaTime()
        let delta = Float(now - startTime)
        startTime = now

        uniforms.time += delta * 0.5

        // State-driven target volumes
        var targetIn: Float = 0
        var targetOut: Float = 0.3
        let t = uniforms.time * 2

        switch state {
        case .idle:
            targetIn = 0
            targetOut = 0.3
        case .listening:
            targetIn = max(audioLevel, 0.15 + 0.35 * sin(t * 3.2))
            targetOut = 0.45
        case .speaking:
            targetIn = max(audioLevel * 0.8, 0.3 + 0.22 * sin(t * 4.8))
            targetOut = max(audioLevel, 0.5 + 0.22 * sin(t * 3.6))
        case .processing:
            let base: Float = 0.38 + 0.07 * sin(t * 0.7)
            let wander: Float = 0.05 * sin(t * 2.1) * sin(t * 0.37 + 1.2)
            targetIn = base + wander
            targetOut = 0.48 + 0.12 * sin(t * 1.05 + 0.6)
        }

        curIn += (targetIn - curIn) * 0.2
        curOut += (targetOut - curOut) * 0.2

        let targetSpeed = 0.1 + (1 - pow(curOut - 1, 2)) * 0.9
        animSpeed += (targetSpeed - animSpeed) * 0.12

        uniforms.animation += delta * animSpeed
        uniforms.inputVolume = curIn
        uniforms.outputVolume = curOut

        // Draw
        let buffer = queue.makeCommandBuffer()!
        let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.size, index: 0)
        if let tex = perlinTexture {
            encoder.setFragmentTexture(tex, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func setup(device: MTLDevice, view: MTKView) {
        commandQueue = device.makeCommandQueue()

        // Full-screen quad: x, y, u, v
        let verts: [Float] = [
            -1, -1, 0, 0,
             1, -1, 1, 0,
            -1,  1, 0, 1,
             1,  1, 1, 1,
        ]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * 4, options: .storageModeShared)

        // Load shader
        guard let library = device.makeDefaultLibrary(),
              let vertFunc = library.makeFunction(name: "orbVertex"),
              let fragFunc = library.makeFunction(name: "orbFragment")
        else {
            print("[OrbRenderer] Failed to load shader functions")
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)

        // Load perlin noise texture
        if let img = UIImage(named: "PerlinNoise")?.cgImage {
            let loader = MTKTextureLoader(device: device)
            perlinTexture = try? loader.newTexture(cgImage: img, options: [
                .SRGB: false,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            ])
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()
        VoiceOrbView(state: .speaking, audioLevel: 0.5)
            .frame(width: 220, height: 220)
    }
}
#endif
