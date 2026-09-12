import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
func image(_ data: Data, _ w: Int, _ h: Int) -> CGImage {
 let provider = CGDataProvider(data: data as CFData)!
 return CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
}
let root = "/Users/levi.napz/projects/wallify/assets/cat/"
let contact = try Data(contentsOf: URL(fileURLWithPath:"/tmp/wallify-sprite-contact.rgba"))
let png = CGImageDestinationCreateWithURL(URL(fileURLWithPath:root+"contact-sheet.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(png,image(contact,1312,1312),nil)
CGImageDestinationFinalize(png)
let movie = try Data(contentsOf: URL(fileURLWithPath:"/tmp/wallify-sprite-animation.rgba"))
let size=164*164*4
let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath:root+"animation-preview.gif") as CFURL,UTType.gif.identifier as CFString,864,nil)!
CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
for n in 0..<864 {
 CGImageDestinationAddImage(gif,image(movie.subdata(in:n*size..<(n+1)*size),164,164),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.0416667]] as CFDictionary)
}
CGImageDestinationFinalize(gif)
