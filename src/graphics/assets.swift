import Foundation
import Darwin

func assetURL(_ name: String) -> URL? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let candidates = [Bundle.main.resourceURL?.appendingPathComponent("assets/\(name)"),
                      executable.appendingPathComponent("../resources/assets/\(name)"),
                      URL(fileURLWithPath: "assets/sprites/bin/\(name)")]
    return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
}

final class SceneAssets {
    private let lock = NSLock()
    private var dirty = true
    private var clearPending = false
    private var initialized = false
    private var loadedPets: UInt8 = 0
    private var artworkStamp: timespec?
    private(set) var hasArtwork = false
    private(set) var generation: UInt64 = 0

    func markArtworkDirty() { lock.lock(); dirty = true; lock.unlock() }
    func clearArtwork() { lock.lock(); clearPending = true; dirty = false; lock.unlock() }

    func initialize() throws {
        guard !initialized else { return }
        var white: UInt32 = 0xffffffff
        loadMetalTexture(Texture.white.rawValue, &white, 1, 1)
        var pixels = [UInt32](repeating: 0, count: 96 * 96)
        for (index, texture) in [Texture.play, .pause, .previous, .next].enumerated() {
            pixels = [UInt32](repeating: 0, count: pixels.count)
            pixels.withUnsafeMutableBufferPointer { drawRasterIcon($0.baseAddress, 96, 96, 48, 48, Int32(index), 0, 1, 2) }
            pixels.withUnsafeBufferPointer { loadMetalTexture(texture.rawValue, $0.baseAddress, 96, 96) }
        }
        pixels = [UInt32](repeating: 0, count: 384 * 384)
        pixels.withUnsafeMutableBufferPointer { _ = drawSpotifyRasterIcon($0.baseAddress, 384, 384, 0, 0, 384) }
        pixels.withUnsafeBufferPointer { loadMetalTexture(Texture.spotify.rawValue, $0.baseAddress, 384, 384) }
        initialized = true
    }

    func ensurePet(_ style: UInt8) throws {
        guard (1...3).contains(style) else { return }
        let bit = UInt8(1) << (style - 1)
        guard loadedPets & bit == 0 else { return }
        let (name, texture, w, h) = [("cat_pixels.bin", Texture.cat, 541, 52),
                                  ("banana_pixels.bin", .banana, 98, 114 * 45), ("raccoon_pixels.bin", .raccoon, 550, 68)][Int(style - 1)]
        guard let url = assetURL(name) else { throw NSError(domain: "Wallify", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing sprite: \(name)"]) }
        let bytes = Array(try Data(contentsOf: url))
        var pixels = [UInt32](repeating: 0, count: w * h)
        let valid = bytes.withUnsafeBufferPointer { input in pixels.withUnsafeMutableBufferPointer {
            decodeSpriteRLE(input.baseAddress, UInt(input.count), $0.baseAddress, UInt($0.count))
        } }
        guard valid else { throw NSError(domain: "Wallify", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid sprite: \(name)"]) }
        pixels.withUnsafeBufferPointer { loadMetalTexture(texture.rawValue, $0.baseAddress, UInt(w), UInt(h)) }
        loadedPets |= bit
    }

    func refreshArtwork() {
        lock.lock()
        let clear = clearPending, refresh = dirty
        clearPending = false; dirty = false
        lock.unlock()
        if clear { hasArtwork = false; artworkStamp = nil }
        guard refresh else { return }
        var info = stat()
        guard stat("/tmp/art.raw", &info) == 0, info.st_size > 0, info.st_size <= 64 * 1024 * 1024 else {
            hasArtwork = false; artworkStamp = nil; widgetStatePointer().pointee.global_has_artwork = false; return
        }
        if let stamp = artworkStamp, stamp.tv_sec == info.st_mtimespec.tv_sec && stamp.tv_nsec == info.st_mtimespec.tv_nsec { return }
        var pixels = [UInt32](repeating: 0, count: 180 * 180)
        let valid = pixels.withUnsafeMutableBufferPointer { decodeArtwork(URL(fileURLWithPath: "/tmp/art.raw"), pixels: $0.baseAddress, width: 180, height: 180) }
        guard valid else { hasArtwork = false; artworkStamp = nil; widgetStatePointer().pointee.global_has_artwork = false; return }
        swapMetalTextures(Texture.artwork.rawValue, Texture.previousArtwork.rawValue)
        swapMetalTextures(Texture.glow.rawValue, Texture.previousGlow.rawValue)
        pixels.withUnsafeBufferPointer { loadMetalTexture(Texture.artwork.rawValue, $0.baseAddress, 180, 180) }
        blurMetalTexture(Texture.artwork.rawValue, Texture.glow.rawValue, 132)
        generation &+= 1
        let state = widgetStatePointer()
        state.pointee.art_transition_until = hasArtwork && state.pointee.setting_animations ? state.pointee.animation_time + 0.5 : 0
        let color = artworkColor(pixels)
        state.pointee.extracted_r = color.0; state.pointee.extracted_g = color.1; state.pointee.extracted_b = color.2
        hasArtwork = true; artworkStamp = info.st_mtimespec
    }
}

func artworkColor(_ pixels: [UInt32]) -> (UInt8, UInt8, UInt8) {
    guard !pixels.isEmpty else { return (0, 0, 0) }
    var sums = [Double](repeating: 0, count: 3)
    for pixel in pixels { for channel in 0..<3 { sums[channel] += Double((pixel >> (channel * 8)) & 255) } }
    let maximum = sums.max()!, boost = maximum > 0 ? max(1, 160 * Double(pixels.count) / maximum) : 1
    let color = sums.map { UInt8(min(255, $0 / Double(pixels.count) * boost)) }
    return (color[0], color[1], color[2])
}

let sceneAssets = SceneAssets()
