import AppKit
import MetalKit
import simd
import SteadyCore

final class ScreenRenderer: NSObject, MTKViewDelegate, CAMetalDisplayLinkDelegate {
    let device: MTLDevice
    private let commands: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private let lock = NSLock()
    private var videoTexture: CVMetalTexture?
    private var frameBuffer: CVPixelBuffer?
    private var grid: MTLTexture?
    private var waiting: MTLTexture?
    private weak var metalLayer: CAMetalLayer?
    private weak var renderView: MTKView?
    private var displayLink: CAMetalDisplayLink?
    private var stopped = false
    var refinedTracking = true {
        didSet {
            configureClock()
            timing.reset()
        }
    }
    var usesDesktop = false
    var scale: Float = 0.85
    var rotation: (Double?) -> simd_quatf = { _ in simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) }
    private(set) var frames = 0
    let timing = RenderTiming()

    init?(_ view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue() else { return nil }
        self.device = device; self.commands = commands
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4x4 transform; float4 geometry; };
        struct Out { float4 position [[position]]; float2 uv; };
        vertex Out screenVertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(0)]]) {
            const float2 corners[] = {float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1)};
            const float2 uv[] = {float2(0,1), float2(1,1), float2(0,0), float2(1,0)};
            float2 p = corners[id] * u.geometry.xy;
            float4 head = u.transform * float4(p.x, p.y, -1, 1);
            Out out;
            out.position = float4(head.x / u.geometry.z, head.y / u.geometry.w, -head.z - 0.01, -head.z);
            out.uv = uv[id];
            return out;
        }
        fragment float4 screenFragment(Out in [[stage_in]], texture2d<float> content [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return float4(content.sample(s, in.uv).rgb, 1);
        }
        """
        do {
            let library = try device.makeLibrary(source: shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "screenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "screenFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch { return nil }
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        view.isPaused = true
        view.device = device
        renderView = view
        metalLayer = view.layer as? CAMetalLayer
        metalLayer?.maximumDrawableCount = 3
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.preferredFramesPerSecond = 120
        view.delegate = self
        grid = makeGrid()
        waiting = makeGrid(waitingForDesktop: true)
        configureClock()
    }
    private func configureClock() {
        guard !stopped else { return }
        renderView?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        renderView?.releaseDrawables()
        if refinedTracking, let metalLayer {
            let link = CAMetalDisplayLink(metalLayer: metalLayer)
            link.delegate = self
            link.preferredFrameLatency = 1
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            renderView?.isPaused = false
        }
    }
    func stop() { stopped = true; renderView?.isPaused = true; displayLink?.invalidate(); displayLink = nil }
    deinit { displayLink?.invalidate() }
    func setFrame(_ buffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }
        var texture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &texture) == kCVReturnSuccess else { return }
        lock.lock(); videoTexture = texture; frameBuffer = buffer; lock.unlock()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        // A queued MTKView callback may still arrive after its timer is paused.
        // nextDrawable is illegal while a CAMetalDisplayLink owns the layer.
        guard !stopped, !refinedTracking, displayLink == nil,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable else { return }
        render(drawable: drawable, predictionTarget: nil)
    }
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard !stopped, refinedTracking, link === displayLink else { return }
        render(drawable: update.drawable, predictionTarget: update.targetPresentationTimestamp)
    }
    private func render(drawable: CAMetalDrawable, predictionTarget: Double?) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let command = commands.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        lock.lock()
        let retainedVideo = videoTexture, retainedBuffer = frameBuffer
        let texture = usesDesktop ? (retainedVideo.flatMap { CVMetalTextureGetTexture($0) } ?? waiting) : grid
        lock.unlock()
        let poseSampleTime = CACurrentMediaTime()
        if let texture {
            let aspect = Float(drawable.texture.width) / Float(drawable.texture.height)
            let contentAspect = Float(texture.width) / Float(texture.height)
            // 46° diagonal FOV from Air 4 Pro specifications, converted to horizontal/vertical tangents.
            let halfDiagonal = tan(Float(46) * .pi / 360)
            let halfY = halfDiagonal / sqrt(1 + aspect * aspect)
            let halfX = halfY * aspect
            let fitX = min(1, contentAspect / aspect)
            let fitY = min(1, aspect / contentAspect)
            struct Uniforms { var transform: simd_float4x4; var geometry: SIMD4<Float> }
            var u = Uniforms(transform: simd_float4x4(rotation(predictionTarget)), geometry: SIMD4(halfX * fitX * scale, halfY * fitY * scale, halfX, halfY))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        drawable.addPresentedHandler { [timing] drawable in
            timing.record(sampledAt: poseSampleTime, presentedAt: drawable.presentedTime)
        }
        command.addCompletedHandler { _ in
            // Keep the IOSurface and its Metal wrapper alive until the GPU is finished with them.
            withExtendedLifetime(retainedVideo) {}
            withExtendedLifetime(retainedBuffer) {}
        }
        command.present(drawable); command.commit(); frames += 1
    }
    private func makeGrid(waitingForDesktop: Bool = false) -> MTLTexture? {
        let width = 1920, height = 1080
        guard let color = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        NSColor(calibratedWhite: 0.065, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineWidth(1)
        context.setStrokeColor(NSColor(calibratedWhite: 0.22, alpha: 1).cgColor)
        for x in stride(from: 0, through: width, by: 120) { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: height)) }
        for y in stride(from: 0, through: height, by: 120) { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: width, y: y)) }
        context.strokePath()
        context.setStrokeColor(NSColor(calibratedWhite: 0.85, alpha: 1).cgColor); context.setLineWidth(4)
        context.stroke(CGRect(x: 3, y: 3, width: width - 6, height: height - 6))
        let text = (waitingForDesktop ? "Connecting to your desktop…" : "Find your comfortable size") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 42, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2, y: 670), withAttributes: attrs)
        let detail = (waitingForDesktop ? "Your Mac screen will appear here." : "All four edges should sit comfortably inside your view.") as NSString
        let detailAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.lightGray]
        detail.draw(at: CGPoint(x: (CGFloat(width) - detail.size(withAttributes: detailAttrs).width) / 2, y: 610), withAttributes: detailAttrs)
        context.setStrokeColor(NSColor.systemTeal.cgColor); context.setLineWidth(3)
        context.move(to: CGPoint(x: 945, y: 540)); context.addLine(to: CGPoint(x: 975, y: 540))
        context.move(to: CGPoint(x: 960, y: 525)); context.addLine(to: CGPoint(x: 960, y: 555)); context.strokePath()
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else { return nil }
        return try? MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
    }
}
