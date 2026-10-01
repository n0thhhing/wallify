import Foundation

final class TextCache {
    private struct Key: Equatable { let text: String; let size: Double; let bold: Bool }
    private struct Entry { var key: Key; var width: Double; var height: Double; var stamp: UInt64 }
    private var entries = [Entry]()
    private var tick: UInt64 = 0
    private var scratch = [UInt32](repeating: 0, count: 2048 * 96)
    var scratchBytes: Int { scratch.count * MemoryLayout<UInt32>.stride }

    private func get(_ text: String, _ size: Double, _ bold: Bool) -> Int? {
        guard !text.isEmpty, size.isFinite, size > 0 else { return nil }
        tick &+= 1
        let key = Key(text: text, size: size, bold: bold)
        if let index = entries.firstIndex(where: { $0.key == key }) { entries[index].stamp = tick; return index }
        let bytes = Array(text.utf8)
        let width = bytes.withUnsafeBufferPointer { min(2048, ceil(rasterTextWidth($0.baseAddress, UInt($0.count), size * 2, bold ? 1 : 0)) + 8) }
        let height = min(96, ceil(size * 3)), w = Int(width), h = Int(height)
        guard w > 0, h > 0 else { return nil }
        scratch.withUnsafeMutableBufferPointer { pixels in
            pixels.baseAddress!.update(repeating: 0, count: w * h)
            bytes.withUnsafeBufferPointer { drawRasterText(pixels.baseAddress, UInt(w), UInt(h), $0.baseAddress, UInt($0.count), 0, 0, width, size * 2, bold ? 1 : 0, 0, 255, 255, 255) }
        }
        let index = entries.count < 16 ? entries.count : entries.indices.min(by: { entries[$0].stamp < entries[$1].stamp })!
        scratch.withUnsafeBufferPointer { loadMetalTexture(Texture.textStart.rawValue + Int32(index), $0.baseAddress, UInt(w), UInt(h)) }
        let entry = Entry(key: key, width: width / 2, height: height / 2, stamp: tick)
        if index == entries.count { entries.append(entry) } else { entries[index] = entry }
        return index
    }

    func width(_ text: String, _ size: Double, _ bold: Bool) -> Double {
        guard let index = get(text, size, bold) else { return 0 }
        return max(0, entries[index].width - 4)
    }

    func draw(_ canvas: Canvas, _ text: String, _ x: Double, _ y: Double, _ viewport: Double,
              _ font: Double, _ scale: Double, _ bold: Bool, _ color: SIMD4<Float>, _ offset: Double = 0,
              _ right: Bool = false, _ ellipsis: Bool = true) {
        guard viewport > 0, scale > 0, let index = get(text, font, bold) else { return }
        let entry = entries[index], full = entry.width * scale, glyphWidth = max(0, full - 4 * scale)
        let crop = max(0, min(offset, full - viewport)), clipped = ellipsis && full - 4 * scale > viewport
        let dotsWidth = clipped ? width("…", font, bold) * scale : 0
        let shown = min(max(0, viewport - dotsWidth), full - crop), origin = right ? x + max(0, viewport - glyphWidth) : x
        let command = canvas.add(Int32(WALLIFY_TEXTURE), Texture.textStart.rawValue + Int32(index), cardRect(origin, y, shown, entry.height * scale), color)
        canvas.commands[command].sx = Float(crop / full); canvas.commands[command].sw = Float(shown / full)
        if clipped { draw(canvas, "…", x + viewport - dotsWidth, y, dotsWidth + 4, font, scale, bold, color, 0, false, false) }
    }
}

let textCache = TextCache()
