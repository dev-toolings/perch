import Foundation
import CoreGraphics
import ImageIO
// usage: px <in> <x> <y> [x y ...] -> prints RGB
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
var i = 2
while i + 1 < a.count {
  let x = Int(a[i])!, y = Int(a[i+1])!
  let off = (y*w + x)*4
  print("(\(x),\(y)) = #\(String(format:"%02X%02X%02X", data[off], data[off+1], data[off+2]))")
  i += 2
}
