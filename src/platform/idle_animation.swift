import AppKit
import Metal
import QuartzCore

private var idleSpriteImages: [Int32: CGImage] = [:]
private var idleAnimationLayer: CALayer?

private func idleSpriteImage(_ textureID: Int32) -> CGImage? {
    if let image = idleSpriteImages[textureID] { return image }
    guard let pointer = wallify_copy_idle_texture(textureID) else { return nil }
    let texture = Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue() as! MTLTexture
    var pixels = Data(count: texture.width * texture.height * 4)
    pixels.withUnsafeMutableBytes {
        texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 4,
                         from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
    }
    guard let provider = CGDataProvider(data: pixels as CFData),
          let image = CGImage(width: texture.width, height: texture.height,
                              bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: texture.width * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
    idleSpriteImages[textureID] = image
    return image
}

func idleKeyframes(_ layer: CALayer, property: String, values: [NSObject],
                   period: Double, phase: Double, speed: Double, started: Double) {
    guard let first = values.first else { return }
    layer.setValue(first, forKeyPath: property)
    guard values.contains(where: { !$0.isEqual(first) }) else { return }
    let animation = CAKeyframeAnimation(keyPath: property)
    animation.values = values
    animation.keyTimes = values.indices.map { NSNumber(value: Double($0) / Double(values.count)) }
    animation.calculationMode = .discrete
    animation.duration = period / speed
    animation.beginTime = started
    animation.timeOffset = phase.truncatingRemainder(dividingBy: period) / speed
    animation.repeatCount = .infinity
    layer.add(animation, forKey: property)
}

func idleCommandLayers(_ root: CALayer, frames: [DrawCommand], frameCount: Int,
                       commandCount: Int, image: CGImage?, period: Double,
                       phase: Double, speed: Double, started: Double) {
    for index in 0..<commandCount {
        let first = frames[index]
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.contents = image
        layer.minificationFilter = .nearest
        layer.magnificationFilter = .nearest
        if image == nil {
            layer.backgroundColor = NSColor(srgbRed: CGFloat(first.r), green: CGFloat(first.g),
                                            blue: CGFloat(first.b), alpha: 1).cgColor
        }
        var positions: [NSObject] = []
        var bounds: [NSObject] = []
        var rects: [NSObject] = []
        var opacities: [NSObject] = []
        for frame in 0..<frameCount {
            let command = frames[frame * commandCount + index]
            positions.append(NSValue(point: NSPoint(x: CGFloat(command.dx - command.clip_x),
                                                    y: CGFloat(command.clip_h - (command.dy - command.clip_y) - command.dh))))
            bounds.append(NSValue(rect: NSRect(x: 0, y: 0, width: CGFloat(command.dw), height: CGFloat(command.dh))))
            rects.append(NSValue(rect: NSRect(x: CGFloat(command.sx), y: CGFloat(command.sy),
                                             width: CGFloat(command.sw), height: CGFloat(command.sh))))
            opacities.append(NSNumber(value: command.alpha))
        }
        root.addSublayer(layer)
        for (property, values) in [("position", positions), ("bounds", bounds),
                                   ("contentsRect", rects), ("opacity", opacities)] {
            idleKeyframes(layer, property: property, values: values, period: period,
                          phase: phase, speed: speed, started: started)
        }
    }
}

public func startIdleAnimation(_ sprites: UnsafePointer<DrawCommand>?, _ spriteCount: UInt, _ spritePeriod: Double,
                               _ effects: UnsafePointer<DrawCommand>?, _ effectFrames: UInt, _ effectCount: UInt,
                               _ effectPeriod: Double, _ phase: Double, _ speed: Double) -> Bool {
    let (totalEffects, overflow) = effectFrames.multipliedReportingOverflow(by: effectCount)
    guard let sprites = sprites, spriteCount > 0, spriteCount <= UInt(Int.max),
          !overflow, totalEffects <= UInt(Int.max), totalEffects == 0 || effects != nil,
          speed.isFinite, speed > 0, phase.isFinite, spritePeriod.isFinite, spritePeriod > 0,
          effectFrames == 0 || (effectPeriod.isFinite && effectPeriod > 0),
          let image = idleSpriteImage(sprites[0].texture_id) else { return false }
    // Own borrowed samples before the main-queue hop.
    let spriteCommands = Array(UnsafeBufferPointer(start: sprites, count: Int(spriteCount)))
    let effectCommands = totalEffects == 0 ? [] : Array(UnsafeBufferPointer(start: effects, count: Int(totalEffects)))
    DispatchQueue.main.async {
        guard let pointer = wallify_idle_surface() else { return }
        let surface = Unmanaged<CALayer>.fromOpaque(pointer).takeUnretainedValue()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        idleAnimationLayer?.removeFromSuperlayer()
        let root = CALayer()
        let first = spriteCommands[0]
        let y = surface.isGeometryFlipped ? CGFloat(first.clip_y) : surface.bounds.height - CGFloat(first.clip_y + first.clip_h)
        root.frame = CGRect(x: CGFloat(first.clip_x), y: y, width: CGFloat(first.clip_w), height: CGFloat(first.clip_h))
        root.isGeometryFlipped = true
        root.masksToBounds = true
        root.cornerRadius = CGFloat(first.clip_radius)
        NSLog("Wallify layer: start idle sprite=%d frame=%@", first.texture_id, NSStringFromRect(root.frame))
        surface.addSublayer(root)
        let started = root.convertTime(CACurrentMediaTime(), from: nil)
        idleCommandLayers(root, frames: spriteCommands, frameCount: Int(spriteCount), commandCount: 1,
                          image: image, period: spritePeriod, phase: phase, speed: speed, started: started)
        if effectFrames > 0 && effectCount > 0 {
            idleCommandLayers(root, frames: effectCommands, frameCount: Int(effectFrames), commandCount: Int(effectCount),
                              image: nil, period: effectPeriod, phase: phase, speed: speed, started: started)
        }
        idleAnimationLayer = root
        CATransaction.commit()
    }
    return true
}

@_cdecl("wallify_idle_animation_stop")
public func stopIdleAnimation() {
    DispatchQueue.main.async {
        if idleAnimationLayer != nil { NSLog("Wallify layer: stop idle") }
        idleAnimationLayer?.removeFromSuperlayer()
        idleAnimationLayer = nil
    }
}
