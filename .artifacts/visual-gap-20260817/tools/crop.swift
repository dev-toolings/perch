import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// usage: crop <in> <out.png> <x> <y> <w> <h> [scale]
let a = CommandLine.arguments
let inURL = URL(fileURLWithPath: a[1]); let outURL = URL(fileURLWithPath: a[2])
let x = Int(a[3])!, y = Int(a[4])!, w = Int(a[5])!, h = Int(a[6])!
let scale = a.count > 7 ? Int(a[7])! : 3
guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("no image") }
guard let cropped = img.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { fatalError("crop") }
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: w*scale, height: h*scale, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .none
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w*scale, height: h*scale))
let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil); CGImageDestinationFinalize(dest)
