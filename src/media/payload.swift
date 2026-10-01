import Foundation

// Spans refer to the caller's bytes; no Swift string storage escapes this call.
func parseMediaPayload(_ bytes: [UInt8], format: Int32) -> WallifyMediaPayload? {
    guard !bytes.isEmpty, bytes.count <= 4096, (0...2).contains(format),
          String(bytes: bytes, encoding: .utf8) != nil else { return nil }
    var start = 0
    var end = bytes.count
    if format == 1 {
        let prefix = Array("fastpotify:now ".utf8)
        if bytes.starts(with: prefix) { start = prefix.count }
        let whitespace: Set<UInt8> = [32, 13, 10]
        while start < end && whitespace.contains(bytes[start]) { start += 1 }
        while end > start && whitespace.contains(bytes[end - 1]) { end -= 1 }
    }
    let delimiter = format == 1 ? "\t" : "|||"
    let fields = String(decoding: bytes[start..<end], as: UTF8.self).components(separatedBy: delimiter)
    guard fields.count >= 3, !(format == 1 && fields[0] == "stopped") else { return nil }
    var spans: [WallifyMediaSpan] = []
    var offset = start
    for field in fields {
        let count = field.utf8.count
        spans.append(WallifyMediaSpan(offset: offset, count: count))
        offset += count + delimiter.utf8.count
    }
    func span(_ index: Int) -> WallifyMediaSpan {
        index < spans.count ? spans[index] : WallifyMediaSpan(offset: end, count: 0)
    }
    func number(_ index: Int) -> Double {
        guard index < fields.count, let value = Double(fields[index]), value.isFinite else { return 0 }
        return max(0, value)
    }
    // Preserve the existing protocol's 512-byte artwork URL bound.
    if format != 2 && span(format == 1 ? 9 : 5).count > 512 { return nil }
    switch format {
    case 1:
        return WallifyMediaPayload(title: span(1), artist: span(2), artwork: span(9),
                                  rate: fields[0] == "playing" ? 1 : 0,
                                  elapsed: number(4) / 1000, duration: number(5) / 1000, has_artwork: false)
    case 2:
        return WallifyMediaPayload(title: span(0), artist: span(1), artwork: span(fields.count),
                                  rate: number(3), elapsed: number(4), duration: number(5), has_artwork: fields[2] == "1")
    default:
        return WallifyMediaPayload(title: span(0), artist: span(1), artwork: span(5),
                                  rate: fields[2] == "playing" ? 1 : 0,
                                  elapsed: number(3), duration: number(4), has_artwork: false)
    }
}

@_cdecl("wallify_parse_media_payload")
public func parseMediaPayloadBridge(_ bytes: UnsafePointer<UInt8>?, _ count: UInt, _ format: Int32,
                                    _ output: UnsafeMutablePointer<WallifyMediaPayload>?) -> Bool {
    guard let output = output else { return false }
    output.pointee = WallifyMediaPayload()
    guard let bytes = bytes, count > 0, count <= 4096,
          let payload = parseMediaPayload(Array(UnsafeBufferPointer(start: bytes, count: Int(count))), format: format) else {
        return false
    }
    output.pointee = payload
    return true
}
