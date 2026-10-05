import AppKit
import Metal
import MetalPerformanceShaders
import QuartzCore
import simd

// GPU setup precedes worker startup. Shared textures, pending scenes, cache
// state, and counters use lock; AppKit presentation stays on the main actor.
final class MetalRenderer: @unchecked Sendable {
    let lock = NSLock()
    private(set) var device: MTLDevice?
    private(set) var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    var surface: CAMetalLayer?
    private var panel: NSPanel?
    private var view: NSView?
    private var width: Int32 = 0
    private var height: Int32 = 0
    private let inFlight = DispatchSemaphore(value: 2)
    private var scheduled = false
    private var latestSize = SIMD2<Float>(repeating: 0)
    private var staticCount = 0
    private var dynamicCount = 0
    private let latestStatic = UnsafeMutablePointer<DrawCommand>.allocate(capacity: Int(WALLIFY_MAX_COMMANDS))
    private let latestDynamic = UnsafeMutablePointer<DrawCommand>.allocate(capacity: Int(WALLIFY_MAX_COMMANDS))
    private let presentStatic = UnsafeMutablePointer<DrawCommand>.allocate(capacity: Int(WALLIFY_MAX_COMMANDS))
    private let presentDynamic = UnsafeMutablePointer<DrawCommand>.allocate(capacity: Int(WALLIFY_MAX_COMMANDS))
    private let cachedStatic = UnsafeMutablePointer<DrawCommand>.allocate(capacity: Int(WALLIFY_MAX_COMMANDS))
    private var textures = [MTLTexture?](repeating: nil, count: Int(WALLIFY_MAX_TEXTURES))
    private var latestTextures = [MTLTexture?](repeating: nil, count: Int(WALLIFY_MAX_TEXTURES))
    private var presentTextures = [MTLTexture?](repeating: nil, count: Int(WALLIFY_MAX_TEXTURES))
    private var cacheTexture: MTLTexture?
    private var cacheValid = false
    private var cachedCount = 0
    private var cachedSize = SIMD2<Float>(repeating: 0)
    private var cachedScale: CGFloat = 0
    private var cacheRebuilds: UInt32 = 0
    var profiling = false
    private var sceneNanos: UInt64 = 0
    private var gpuNanos: UInt64 = 0
    private var uploadedBytes: UInt64 = 0
    private var sceneFrames: UInt64 = 0
    private var renderedFrames: UInt64 = 0
    private var drawCalls: UInt64 = 0
    private var performance = PerformanceSample()

    init() {
        for buffer in [latestStatic, latestDynamic, presentStatic, presentDynamic, cachedStatic] {
            buffer.initialize(repeating: DrawCommand(), count: Int(WALLIFY_MAX_COMMANDS))
        }
    }

    deinit {
        for buffer in [latestStatic, latestDynamic, presentStatic, presentDynamic, cachedStatic] {
            buffer.deinitialize(count: Int(WALLIFY_MAX_COMMANDS))
            buffer.deallocate()
        }
    }

    func initialize(libraryURL: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Wallify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device or command queue unavailable"])
        }
        let library = try device.makeLibrary(URL: libraryURL)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Wallify GPU compositor"
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func encode(_ command: MTLCommandBuffer, target: MTLTexture, commands: UnsafePointer<DrawCommand>,
                count: Int, size: SIMD2<Float>, textures: [MTLTexture?], cachedScene: MTLTexture? = nil) -> Bool {
        guard let pipeline = pipeline else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        if count > 0 {
            let length = count * MemoryLayout<DrawCommand>.stride
            // Inline encoder bytes are limited to 4 KB. Use an owned buffer above
            // that limit so a valid large scene does not fail Metal validation.
            if length > 4096 {
                guard let buffer = device?.makeBuffer(bytes: commands, length: length, options: .storageModeShared) else {
                    encoder.endEncoding()
                    return false
                }
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            } else {
                encoder.setVertexBytes(commands, length: length, index: 0)
                encoder.setFragmentBytes(commands, length: length, index: 0)
            }
            var viewport = size
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.setFragmentTextures(textures, range: 0..<Int(WALLIFY_MAX_TEXTURES))
            if let cachedScene = cachedScene { encoder.setFragmentTexture(cachedScene, index: Int(WALLIFY_CACHED_SCENE_TEXTURE)) }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()
        return true
    }

    func texture(_ slot: Int32) -> MTLTexture? {
        guard slot >= 0, slot < WALLIFY_MAX_TEXTURES else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return textures[Int(slot)]
    }

    func loadTexture(_ slot: Int32, pixels: UnsafePointer<UInt32>?, width: UInt, height: UInt) {
        guard slot >= 0, slot < WALLIFY_MAX_TEXTURES, let pixels = pixels,
              width > 0, height > 0, width <= 16384, height <= 16384, let device = device else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: Int(width), height: Int(height), mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, Int(width), Int(height)), mipmapLevel: 0, withBytes: pixels, bytesPerRow: Int(width * 4))
        lock.lock()
        textures[Int(slot)] = texture
        if profiling { uploadedBytes += UInt64(width * height * 4) }
        lock.unlock()
        NSLog("Wallify: texture upload id=%d size=%lux%lu", slot, width, height)
    }

    func swapTextures(_ source: Int32, _ destination: Int32) {
        guard source >= 0, source < WALLIFY_MAX_TEXTURES, destination >= 0, destination < WALLIFY_MAX_TEXTURES else { return }
        lock.lock()
        textures.swapAt(Int(source), Int(destination))
        lock.unlock()
    }

    func encodeScene(_ command: MTLCommandBuffer, target: MTLTexture,
                     staticCommands: UnsafePointer<DrawCommand>, staticCount: Int,
                     dynamicCommands: UnsafePointer<DrawCommand>, dynamicCount: Int,
                     size: SIMD2<Float>, scale: CGFloat, textures: [MTLTexture?]) -> Bool {
        guard let device = device, staticCount >= 0, staticCount <= WALLIFY_MAX_COMMANDS,
              dynamicCount >= 0, dynamicCount <= WALLIFY_MAX_COMMANDS,
              size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
              scale.isFinite, scale > 0 else { return false }
        let width = ceil(CGFloat(size.x) * scale), height = ceil(CGFloat(size.y) * scale)
        guard width <= 16384, height <= 16384 else { return false }
        // Cache bookkeeping and metrics share the renderer lock; encoding never waits for the GPU.
        lock.lock()
        defer { lock.unlock() }
        if cacheTexture?.width != Int(width) || cacheTexture?.height != Int(height) {
            NSLog("Wallify: static scene texture resize -> %.0fx%.0f (scale %.2f)", width, height, scale)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: max(1, Int(width)), height: max(1, Int(height)), mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            cacheTexture = device.makeTexture(descriptor: descriptor)
            cacheValid = false
        }
        guard let cachedTexture = cacheTexture else { return false }
        let changed = !cacheValid || cachedCount != staticCount || cachedSize != size || cachedScale != scale ||
            (staticCount > 0 && memcmp(cachedStatic, staticCommands, staticCount * MemoryLayout<DrawCommand>.stride) != 0)
        if changed {
            NSLog("Wallify: rebuilding static cache cmds=%d size=%.0fx%.0f", staticCount, size.x, size.y)
            guard encode(command, target: cachedTexture, commands: staticCommands, count: staticCount, size: size, textures: textures) else { return false }
            cachedStatic.update(from: staticCommands, count: staticCount)
            cachedCount = staticCount
            cachedSize = size
            cachedScale = scale
            cacheValid = true
            cacheRebuilds &+= 1
        }
        guard encode(command, target: target, commands: dynamicCommands, count: dynamicCount,
                     size: size, textures: textures, cachedScene: cachedTexture) else { return false }
        if profiling { drawCalls += changed ? 2 : 1 }
        return true
    }

    func blurTexture(_ source: Int32, _ destination: Int32, artSize: Float) {
        guard destination >= 0, destination < WALLIFY_MAX_TEXTURES, artSize.isFinite, artSize > 0, artSize <= 8192,
              let input = texture(source), let device = device, let queue = queue else { return }
        let bakeScale = Float(WALLIFY_GLOW_BAKE_SCALE)
        let extent = Int(ceil(glowExtent(artSize) * bakeScale))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: extent, height: extent, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let padded = device.makeTexture(descriptor: descriptor), let output = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer() else { return }
        command.label = "Artwork glow bake"
        var draw = DrawCommand()
        draw.kind = WALLIFY_GLOW_SOURCE
        draw.dw = Float(Int(artSize * Float(WALLIFY_GLOW_SCALE_X) * bakeScale))
        draw.dh = Float(Int(artSize * Float(WALLIFY_GLOW_SCALE_Y) * bakeScale))
        draw.dx = (Float(extent) - draw.dw) * 0.5
        draw.dy = (Float(extent) - draw.dh) * 0.5
        draw.sw = 1; draw.sh = 1
        draw.r = 1; draw.g = 1; draw.b = 1; draw.alpha = 1
        draw.radius = artSize * 0.1 * bakeScale
        let encoded = withUnsafePointer(to: &draw) {
            encode(command, target: padded, commands: $0, count: 1, size: SIMD2(repeating: Float(extent)),
                   textures: [MTLTexture?](repeating: input, count: Int(WALLIFY_MAX_TEXTURES)))
        }
        guard encoded else { return }
        let blur = MPSImageGaussianBlur(device: device, sigma: Float(WALLIFY_GLOW_BAKE_BLUR))
        blur.edgeMode = .zero
        blur.encode(commandBuffer: command, sourceTexture: padded, destinationTexture: output)
        command.addCompletedHandler { completed in
            if completed.status == .error { NSLog("Wallify glow GPU error: %@", completed.error?.localizedDescription ?? "Unknown") }
        }
        command.commit()
        lock.lock()
        textures[Int(destination)] = output
        lock.unlock()
    }

    @MainActor func createWindow(width: Int32, height: Int32, left: Int32, top: Int32) -> Bool {
        guard width > 0, height > 0 else { return false }
        let libraryURL = Bundle.main.url(forResource: "default", withExtension: "metallib") ??
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("default.metallib")
        guard let libraryURL = libraryURL else { return false }
        do { try initialize(libraryURL: libraryURL) }
        catch { NSLog("Wallify: Metal initialization failed: %@", error.localizedDescription); return false }
        profiling = ProcessInfo.processInfo.environment["WALLIFY_PROFILE"] != nil
        NSLog("Wallify: create %dx%d at %d,%d profiling=%@", width, height, left, top, profiling ? "on" : "off")
        resize(width: width, height: height)
        if terminalMode { return true }
        let panel = Unmanaged<NSPanel>.fromOpaque(createWidgetPanel(width, height)).takeRetainedValue()
        let view = Unmanaged<NSView>.fromOpaque(createWidgetView(width, height)).takeRetainedValue()
        let surface = CAMetalLayer()
        surface.device = device
        surface.pixelFormat = .bgra8Unorm
        surface.framebufferOnly = true
        surface.presentsWithTransaction = true
        surface.isOpaque = false
        surface.contentsScale = NSScreen.main?.backingScaleFactor ?? 1
        view.wantsLayer = true
        view.layer = surface
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Int(width), height: Int(height)))
        container.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        panel.contentView = container
        self.panel = panel
        self.view = view
        self.surface = surface
        moveWidgetPanelNow(left, top)
        NSLog("Wallify window: show widget id=%d frame=%@", panel.windowNumber, NSStringFromRect(panel.frame))
        panel.makeKeyAndOrderFront(nil)
        wallify_set_window_visible(panel.occlusionState.contains(.visible) ? 1 : 0)
        installStatusMenu()
        return true
    }

    func submit(size: SIMD2<Float>, staticCommands: UnsafePointer<DrawCommand>?, staticCount: UInt,
                dynamicCommands: UnsafePointer<DrawCommand>?, dynamicCount: UInt) {
        guard staticCount <= WALLIFY_MAX_COMMANDS, dynamicCount <= WALLIFY_MAX_COMMANDS,
              staticCount == 0 || staticCommands != nil, dynamicCount == 0 || dynamicCommands != nil,
              size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0 else { return }
        lock.lock()
        if staticCount > 0 { latestStatic.update(from: staticCommands!, count: Int(staticCount)) }
        if dynamicCount > 0 { latestDynamic.update(from: dynamicCommands!, count: Int(dynamicCount)) }
        self.staticCount = Int(staticCount)
        self.dynamicCount = Int(dynamicCount)
        latestSize = size
        for index in textures.indices { latestTextures[index] = textures[index] }
        let enqueue = !scheduled
        scheduled = true
        lock.unlock()
        if enqueue { DispatchQueue.main.async { self.presentLatest() } }
    }

    @MainActor private func presentLatest() {
        autoreleasepool {
            lock.lock()
            guard scheduled, inFlight.wait(timeout: .now()) == .success else { lock.unlock(); return }
            let statics = staticCount, dynamics = dynamicCount, size = latestSize
            presentStatic.update(from: latestStatic, count: statics)
            presentDynamic.update(from: latestDynamic, count: dynamics)
            for index in textures.indices { presentTextures[index] = latestTextures[index] ?? textures[0] }
            scheduled = false
            lock.unlock()
            var submitted = false
            defer { if !submitted { inFlight.signal() } }
            if let terminal = TerminalDisplay.current {
                terminal.present(self, size: size, statics: presentStatic, staticCount: statics,
                    dynamics: presentDynamic, dynamicCount: dynamics, textures: presentTextures)
                return
            }
            guard dynamics > 0, let surface = surface, let panel = panel else { return }
            let drawableSize = CGSize(width: CGFloat(size.x) * surface.contentsScale, height: CGFloat(size.y) * surface.contentsScale)
            if surface.drawableSize != drawableSize { surface.drawableSize = drawableSize }
            guard let drawable = surface.nextDrawable(), let command = queue?.makeCommandBuffer() else { return }
            command.label = "Wallify scene"
            guard encodeScene(command, target: drawable.texture, staticCommands: presentStatic, staticCount: statics,
                dynamicCommands: presentDynamic, dynamicCount: dynamics, size: size, scale: surface.contentsScale, textures: presentTextures) else { return }
            command.addCompletedHandler { completed in
                self.lock.lock()
                if completed.status == .error {
                    self.cacheValid = false
                    NSLog("Wallify GPU error: %@", completed.error?.localizedDescription ?? "Unknown")
                }
                self.renderedFrames &+= 1
                let duration = max(0, completed.gpuEndTime - completed.gpuStartTime)
                if duration.isFinite { self.gpuNanos &+= UInt64(duration * 1e9) }
                let pending = self.scheduled
                self.lock.unlock()
                self.inFlight.signal()
                if pending { DispatchQueue.main.async { self.presentLatest() } }
            }
            submitted = true
            command.commit()
            command.waitUntilScheduled()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            var frame = panel.frame
            if frame.width != CGFloat(size.x) || frame.height != CGFloat(size.y) {
                let top = frame.maxY
                frame.size = NSSize(width: CGFloat(size.x), height: CGFloat(size.y))
                frame.origin.y = top - frame.height
                panel.setFrame(frame, display: false)
            }
            drawable.present()
            CATransaction.commit()
        }
    }

    func resize(width: Int32, height: Int32) {
        guard width > 0, height > 0 else { return }
        lock.lock()
        self.width = width
        self.height = height
        lock.unlock()
    }

    func dimensions() -> (Int32, Int32) {
        lock.lock()
        defer { lock.unlock() }
        return (width, height)
    }

    func profileScene(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0, seconds < Double(UInt64.max) / 1e9 else { return }
        lock.lock()
        sceneNanos &+= UInt64(seconds * 1e9)
        sceneFrames &+= 1
        if profiling && sceneFrames % 300 == 0 {
            NSLog("Wallify profile: frames=%llu scene_cpu_ms=%.3f gpu_ms=%.3f commands_per_frame=%.1f asset_upload_bytes=%llu full_frame_upload_bytes=0",
                  sceneFrames, Double(sceneNanos) / Double(sceneFrames) / 1e6,
                  renderedFrames == 0 ? 0 : Double(gpuNanos) / Double(renderedFrames) / 1e6,
                  renderedFrames == 0 ? 0 : Double(drawCalls) / Double(renderedFrames), uploadedBytes)
        }
        lock.unlock()
    }

    func stats() -> WallifyRendererStats {
        lock.lock()
        defer { lock.unlock() }
        var stats = WallifyRendererStats()
        let now = monotonicTime()
        if now - performance.time >= 1 {
            var usage = rusage()
            if getrusage(RUSAGE_SELF, &usage) == 0 {
                let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
                    Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
                performance.update(now: now, cpu: cpu, frames: renderedFrames, gpu: gpuNanos)
            }
        }
        stats.cpu_percent = performance.cpuPercent
        stats.redraws_per_second = performance.redraws
        stats.live_gpu_ms = performance.gpuMS
        let name = Array((device?.name ?? "Unavailable").utf8.prefix(127))
        withUnsafeMutableBytes(of: &stats.device_name) { bytes in
            for (index, byte) in name.enumerated() { bytes[index] = byte }
        }
        stats.ready = device != nil && pipeline != nil && surface != nil ? 1 : 0
        stats.profiling = profiling ? 1 : 0
        stats.pending = scheduled ? 1 : 0
        stats.command_count = UInt32(dynamicCount)
        stats.scene_frames = sceneFrames; stats.rendered_frames = renderedFrames
        stats.uploaded_bytes = uploadedBytes; stats.draw_calls = drawCalls
        stats.scene_ms = sceneFrames == 0 ? 0 : Double(sceneNanos) / Double(sceneFrames) / 1e6
        stats.gpu_ms = renderedFrames == 0 ? 0 : Double(gpuNanos) / Double(renderedFrames) / 1e6
        stats.logical_width = Double(latestSize.x); stats.logical_height = Double(latestSize.y)
        for texture in textures.compactMap({ $0 }) {
            stats.texture_count += 1
            stats.texture_bytes += UInt64(texture.allocatedSize)
        }
        stats.drawable_width = Double(surface?.drawableSize.width ?? 0)
        stats.drawable_height = Double(surface?.drawableSize.height ?? 0)
        stats.scale = Double(surface?.contentsScale ?? 0)
        stats.static_cache_valid = cacheValid ? 1 : 0
        stats.static_cache_rebuilds = cacheRebuilds
        stats.static_cache_width = Double(cacheTexture?.width ?? 0)
        stats.static_cache_height = Double(cacheTexture?.height ?? 0)
        return stats
    }
}

func glowExtent(_ artSize: Float) -> Float {
    ceil(artSize * max(Float(WALLIFY_GLOW_SCALE_X), Float(WALLIFY_GLOW_SCALE_Y)) + 6 * Float(WALLIFY_GLOW_BLUR))
}

let metalRenderer = MetalRenderer()

@_cdecl("wallify_create")
@MainActor public func createMetalWidget(_ width: Int32, _ height: Int32, _ left: Int32, _ top: Int32) -> Bool {
    metalRenderer.createWindow(width: width, height: height, left: left, top: top)
}

@_cdecl("wallify_present_split")
public func presentMetalScene(_ width: Float, _ height: Float, _ statics: UnsafePointer<DrawCommand>?, _ staticCount: UInt,
                              _ dynamics: UnsafePointer<DrawCommand>?, _ dynamicCount: UInt) {
    metalRenderer.submit(size: SIMD2(width, height), staticCommands: statics, staticCount: staticCount,
                         dynamicCommands: dynamics, dynamicCount: dynamicCount)
}

@_cdecl("wallify_present")
public func presentMetalCommands(_ width: Float, _ height: Float, _ commands: UnsafePointer<DrawCommand>?, _ count: UInt) {
    metalRenderer.submit(size: SIMD2(width, height), staticCommands: nil, staticCount: 0, dynamicCommands: commands, dynamicCount: count)
}

@_cdecl("wallify_load_texture")
public func loadMetalTexture(_ slot: Int32, _ pixels: UnsafePointer<UInt32>?, _ width: UInt, _ height: UInt) {
    autoreleasepool { metalRenderer.loadTexture(slot, pixels: pixels, width: width, height: height) }
}

@_cdecl("wallify_swap_textures")
public func swapMetalTextures(_ source: Int32, _ destination: Int32) { metalRenderer.swapTextures(source, destination) }

@_cdecl("wallify_blur_texture")
public func blurMetalTexture(_ source: Int32, _ destination: Int32, _ artSize: Float) {
    autoreleasepool { metalRenderer.blurTexture(source, destination, artSize: artSize) }
}

@_cdecl("wallify_glow_extent")
public func metalGlowExtent(_ artSize: Float) -> Float { glowExtent(artSize) }

@_cdecl("wallify_resize")
public func resizeMetalWidget(_ width: Int32, _ height: Int32) { metalRenderer.resize(width: width, height: height) }

@_cdecl("wallify_width")
public func metalWidgetWidth() -> Int32 { metalRenderer.dimensions().0 }
@_cdecl("wallify_height")
public func metalWidgetHeight() -> Int32 { metalRenderer.dimensions().1 }

@_cdecl("wallify_debug_renderer_stats")
public func metalRendererStats(_ output: UnsafeMutablePointer<WallifyRendererStats>?) { output?.pointee = metalRenderer.stats() }
@_cdecl("wallify_profile_scene")
public func profileMetalScene(_ seconds: Double) { metalRenderer.profileScene(seconds) }

@_cdecl("wallify_copy_idle_texture")
public func copyIdleMetalTexture(_ slot: Int32) -> UnsafeMutableRawPointer? {
    metalRenderer.texture(slot).map { Unmanaged.passRetained($0 as AnyObject).toOpaque() }
}
@_cdecl("wallify_idle_surface")
public func idleMetalSurface() -> UnsafeMutableRawPointer? {
    metalRenderer.surface.map { Unmanaged.passUnretained($0).toOpaque() }
}
@_cdecl("wallify_context_menu_view")
@MainActor public func metalContextMenuView() -> UnsafeMutableRawPointer? {
    WidgetView.current.map { Unmanaged.passUnretained($0).toOpaque() }
}
