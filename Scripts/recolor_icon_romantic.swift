import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage: recolor.swift SOURCE.png OUTPUT.png
let args = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

typealias RGB = (Double, Double, Double)
func hex(_ v: UInt32) -> RGB { (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255) }
func lum(_ c: RGB) -> Double { 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
func scale(_ a: RGB, _ k: Double) -> RGB { (a.0 * k, a.1 * k, a.2 * k) }
func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }

let bgRef = hex(0x251126), ivoryRef = hex(0xE3D2C0), orangeRef = hex(0xC8683E)
let grapeTop = hex(0xBBA2E3), grapeBottom = hex(0x8F70C8)       // 葡萄紫 gradient around #A78AD4
let pearl = hex(0xFFF3EE)                                         // 珍珠白, a touch brighter than #FFF1E9
let sakura = hex(0xEAA2C2)                                        // 樱花粉, deepened from #F5B5CF to read on pearl
let lBg = lum(bgRef), lOrange = lum(orangeRef)
let ivoryRatio: RGB = (pearl.0 / ivoryRef.0, pearl.1 / ivoryRef.1, pearl.2 / ivoryRef.2)

for y in 0..<h {
    let gradient = mix(grapeTop, grapeBottom, Double(y) / Double(h - 1))
    for x in 0..<w {
        let i = (y * w + x) * 4
        let a = Double(buf[i + 3]) / 255
        if a == 0 { continue }
        let c: RGB = (Double(buf[i]) / 255 / a, Double(buf[i + 1]) / 255 / a, Double(buf[i + 2]) / 255 / a)
        let l = lum(c)
        let mx = max(c.0, c.1, c.2), mn = min(c.0, c.1, c.2)
        let sat = mx > 0 ? (mx - mn) / mx : 0

        // Background: purple gradient, keeping the original shading (vignette, drop shadows).
        let shade = min(max(pow(l / lBg, 0.30), 0.80), 1.12)
        let bgOut = scale(gradient, shade)
        // Paper: per-channel ratio keeps texture and folds.
        let paperOut: RGB = (c.0 * ivoryRatio.0, c.1 * ivoryRatio.1, c.2 * ivoryRatio.2)
        // Accent: sakura pink scaled by original brightness.
        let accentOut = scale(sakura, min(max(pow(l / lOrange, 0.6), 0.75), 1.10))

        let paperness = smooth(0.14, 0.50, l)
        let isWarm = c.0 > c.2 + 0.05 && c.0 >= c.1
        let accentness = isWarm ? smooth(0.32, 0.52, sat) * smooth(0.10, 0.22, l) : 0
        var out = mix(mix(bgOut, paperOut, paperness), accentOut, accentness)
        // Soft outer drop shadow (semi-transparent dark pixels): keep it a shadow, tinted deep purple.
        let bodyness = smooth(0.62, 0.95, a)
        let shadowTint = scale(hex(0x2A1A40), min(max(l / lBg, 0.4), 1.0))
        out = mix(shadowTint, out, bodyness)
        out = (min(out.0, 1), min(out.1, 1), min(out.2, 1))
        buf[i] = UInt8((out.0 * a * 255).rounded())
        buf[i + 1] = UInt8((out.1 * a * 255).rounded())
        buf[i + 2] = UInt8((out.2 * a * 255).rounded())
    }
}
let outImg = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, outImg, nil)
CGImageDestinationFinalize(dest)
print("wrote", args[2])
