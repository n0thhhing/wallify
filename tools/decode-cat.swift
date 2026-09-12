import Foundation
import CoreGraphics
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("decode-cat: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5, let width = Int(args[3]), let height = Int(args[4]),
      width > 0, height > 0 else {
    fail("usage: decode-cat.swift INPUT.png OUTPUT.rgba WIDTH HEIGHT")
}
let url = URL(fileURLWithPath: args[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot decode \(args[1])")
}
guard image.width == width, image.height == height else {
    fail("expected \(width)x\(height), got \(image.width)x\(image.height)")
}
var bytes = [UInt8](repeating: 0, count: width * height * 4)
bytes.withUnsafeMutableBytes { ptr in
    guard let context = CGContext(
        data: ptr.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("cannot create RGBA bitmap context")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}
do {
    try Data(bytes).write(to: URL(fileURLWithPath: args[2]))
} catch {
    fail("cannot write \(args[2]): \(error)")
}
