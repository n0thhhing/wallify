import AppKit
import CoreText
import ImageIO

func rasterContext(_ pixels: UnsafeMutablePointer<UInt32>?, width: UInt, height: UInt) -> CGContext? {
    guard let pixels = pixels, width > 0, height > 0,
          width <= UInt(Int.max / 4), height <= UInt(Int.max) / (width * 4) else { return nil }
    return CGContext(data: pixels, width: Int(width), height: Int(height), bitsPerComponent: 8,
                     bytesPerRow: Int(width * 4), space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
}

private func rasterText(_ utf8: UnsafePointer<UInt8>?, length: UInt, fontSize: Double,
                        bold: Int32, color: CGColor? = nil) -> NSAttributedString? {
    guard let utf8 = utf8, length > 0, length <= UInt(Int.max), fontSize.isFinite, fontSize > 0,
          let text = String(bytes: UnsafeBufferPointer(start: utf8, count: Int(length)), encoding: .utf8),
          let font = CTFontCreateUIFontForLanguage(bold == 0 ? .system : .emphasizedSystem, fontSize, nil) else { return nil }
    var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    if let color = color { attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
    return NSAttributedString(string: text, attributes: attributes)
}

@_cdecl("widget_text_width")
public func rasterTextWidth(_ utf8: UnsafePointer<UInt8>?, _ length: UInt, _ fontSize: Double, _ bold: Int32) -> Double {
    autoreleasepool {
        guard let text = rasterText(utf8, length: length, fontSize: fontSize, bold: bold) else { return 0 }
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
    }
}

@_cdecl("widget_text")
public func drawRasterText(_ pixels: UnsafeMutablePointer<UInt32>?, _ width: UInt, _ height: UInt,
                           _ utf8: UnsafePointer<UInt8>?, _ length: UInt, _ x: Double, _ y: Double,
                           _ maxWidth: Double, _ fontSize: Double, _ bold: Int32, _ rightAlign: Int32,
                           _ red: UInt8, _ green: UInt8, _ blue: UInt8) {
    guard x.isFinite, y.isFinite, maxWidth.isFinite, maxWidth > 0 else { return }
    autoreleasepool {
        let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                            components: [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1])!
        guard let text = rasterText(utf8, length: length, fontSize: fontSize, bold: bold, color: color),
              let context = rasterContext(pixels, width: width, height: height) else { return }
        var line = CTLineCreateWithAttributedString(text)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: text.attributes(at: 0, effectiveRange: nil)))
            if let truncated = CTLineCreateTruncatedLine(line, maxWidth, .end, token) { line = truncated }
        }
        var ascent: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        context.clip(to: CGRect(x: x, y: 0, width: maxWidth, height: Double(height)))
        context.setShouldAntialias(true)
        context.textPosition = CGPoint(x: x + (rightAlign == 0 ? 0 : maxWidth - lineWidth), y: Double(height) - y - ascent)
        CTLineDraw(line, context)
    }
}

private let rasterSymbols: [(CGImage, NSSize)?] = {
    autoreleasepool {
        ["play.fill", "pause.fill", "backward.fill", "forward.fill"].enumerated().map { index, name in
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
                  let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: index < 2 ? 28 : 17, weight: .regular)) else { return nil }
            let size = configured.size
            // An owned bitmap avoids lockFocus's implicit offscreen window/focus stack.
            guard let raster = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(size.width * 3)), pixelsHigh: Int(ceil(size.height * 3)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
                let context = NSGraphicsContext(bitmapImageRep: raster) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let rect = NSRect(x: 0, y: 0, width: raster.pixelsWide, height: raster.pixelsHigh)
            context.cgContext.clear(rect)
            configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            guard let image = raster.cgImage else { return nil }
            return (image, size)
        }
    }
}()

@_cdecl("widget_draw_symbol")
public func drawRasterSymbol(_ pointer: UnsafeMutableRawPointer?, _ kind: Int32) -> Int32 {
    guard let pointer = pointer, kind >= 0, kind < 4, let (image, size) = rasterSymbols[Int(kind)] else { return 0 }
    let context = Unmanaged<CGContext>.fromOpaque(pointer).takeUnretainedValue()
    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    context.saveGState()
    context.clip(to: rect, mask: image)
    context.fill(rect)
    context.restoreGState()
    return 1
}

private func rasterTriangle(_ context: CGContext, x: CGFloat, width: CGFloat, height: CGFloat) {
    context.beginPath()
    context.move(to: CGPoint(x: x, y: -height / 2))
    context.addLine(to: CGPoint(x: x + width, y: 0))
    context.addLine(to: CGPoint(x: x, y: height / 2))
    context.closePath()
    context.drawPath(using: .fillStroke)
}

@_cdecl("widget_icon")
public func drawRasterIcon(_ pixels: UnsafeMutablePointer<UInt32>?, _ width: UInt, _ height: UInt,
                           _ x: Double, _ y: Double, _ kind: Int32, _ hover: Double,
                           _ opacity: Double, _ scale: Double) {
    guard kind >= 0, kind < 4, x.isFinite, y.isFinite, opacity.isFinite, scale.isFinite, scale > 0,
          let context = rasterContext(pixels, width: width, height: height) else { return }
    context.translateBy(x: x, y: Double(height) - y)
    context.scaleBy(x: scale, y: scale)
    context.setAlpha(opacity)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    defer { context.endTransparencyLayer() }
    context.setFillColor(red: 0.83, green: 0.83, blue: 0.83, alpha: 1)
    context.setStrokeColor(red: 0.83, green: 0.83, blue: 0.83, alpha: 1)
    context.setLineJoin(.round)
    context.setLineWidth(1.6)
    if drawRasterSymbol(Unmanaged.passUnretained(context).toOpaque(), kind) != 0 { return }
    switch kind {
    case 0: rasterTriangle(context, x: -7, width: 18, height: 23)
    case 1:
        for x: CGFloat in [-8, 2] {
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: -12, width: 6, height: 24), cornerWidth: 1.8, cornerHeight: 1.8, transform: nil))
        }
        context.fillPath()
    default:
        if kind == 2 { context.scaleBy(x: -1, y: 1) }
        rasterTriangle(context, x: -8, width: 9, height: 12)
        rasterTriangle(context, x: 2, width: 9, height: 12)
    }
}

private var spotifyRasterIcon: CGImage?

@_cdecl("widget_spotify_icon")
public func drawSpotifyRasterIcon(_ pixels: UnsafeMutablePointer<UInt32>?, _ width: UInt, _ height: UInt,
                                  _ x: Double, _ y: Double, _ size: Double) -> Int32 {
    guard x.isFinite, y.isFinite, size.isFinite, size > 0,
          let context = rasterContext(pixels, width: width, height: height) else { return 0 }
    if spotifyRasterIcon == nil {
        for path in ["/Applications/Spotify.app/Contents/Resources/AppIcon.icns", "assets/spotify_icon.png"] {
            if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { spotifyRasterIcon = image; break }
        }
    }
    guard let image = spotifyRasterIcon else { return 0 }
    context.draw(image, in: CGRect(x: x, y: Double(height) - y - size, width: size, height: size))
    return 1
}

func decodeArtwork(_ url: URL, pixels: UnsafeMutablePointer<UInt32>?, width: UInt, height: UInt) -> Bool {
    guard let context = rasterContext(pixels, width: width, height: height),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
              [kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    return true
}

@_cdecl("widget_artwork_pixels")
public func artworkRasterPixels(_ pixels: UnsafeMutablePointer<UInt32>?, _ width: UInt, _ height: UInt,
                                _ path: UnsafePointer<UInt8>?, _ length: UInt) -> Bool {
    guard let path = path, length <= UInt(Int.max),
          let string = String(bytes: UnsafeBufferPointer(start: path, count: Int(length)), encoding: .utf8) else { return false }
    return autoreleasepool { decodeArtwork(URL(fileURLWithPath: string), pixels: pixels, width: width, height: height) }
}
