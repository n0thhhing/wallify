import Foundation
import CoreGraphics
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("decode-cat: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 5, let width = Int(args[3]), let height = Int(args[4]),
      width > 0, height > 0 else {
    fail("usage: decode-cat.swift INPUT.png OUTPUT.rgba WIDTH HEIGHT [SCALE]")
}
let scale = args.count > 5 ? (Double(args[5]) ?? 1.0) : 1.0
let targetWidth = Int(Double(width) * scale)
let targetHeight = Int(Double(height) * scale)

let url = URL(fileURLWithPath: args[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot decode \(args[1])")
}

var bytes = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
bytes.withUnsafeMutableBytes { ptr in
    guard let context = CGContext(
        data: ptr.baseAddress, width: targetWidth, height: targetHeight,
        bitsPerComponent: 8, bytesPerRow: targetWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("cannot create RGBA bitmap context")
    }
    // High quality interpolation for downscaling
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
}

var outData = Data()
var i = 0
let total = targetWidth * targetHeight
// We break runs at frame boundaries for banana cat (98x114 before scale).
// Since banana cat isn't scaled, targetWidth = 98, targetHeight = 5130. Frame area = 98*114.
let frameArea = 98 * 114 

func pixelsEqual(_ a: Int, _ b: Int) -> Bool {
    return bytes[a*4] == bytes[b*4] && bytes[a*4+1] == bytes[b*4+1] &&
           bytes[a*4+2] == bytes[b*4+2] && bytes[a*4+3] == bytes[b*4+3]
}

while i < total {
    var runLength = 1
    while runLength < 127 && i + runLength < total && pixelsEqual(i, i + runLength) {
        if (i + runLength) % frameArea == 0 { break }
        runLength += 1
    }
    
    if runLength > 1 || i == total - 1 {
        outData.append(UInt8(runLength) | 0x80)
        outData.append(bytes[i*4])
        outData.append(bytes[i*4+1])
        outData.append(bytes[i*4+2])
        outData.append(bytes[i*4+3])
        i += runLength
    } else {
        var seqLength = 1
        while seqLength < 127 && i + seqLength < total {
            if (i + seqLength) % frameArea == 0 { break }
            if i + seqLength + 1 < total && pixelsEqual(i + seqLength, i + seqLength + 1) {
                if (i + seqLength + 1) % frameArea != 0 {
                    break
                }
            }
            seqLength += 1
        }
        outData.append(UInt8(seqLength))
        for j in 0..<seqLength {
            outData.append(bytes[(i+j)*4])
            outData.append(bytes[(i+j)*4+1])
            outData.append(bytes[(i+j)*4+2])
            outData.append(bytes[(i+j)*4+3])
        }
        i += seqLength
    }
}

do {
    try outData.write(to: URL(fileURLWithPath: args[2]))
} catch {
    fail("cannot write \(args[2]): \(error)")
}
