import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: apply_alpha_mask.swift SOURCE.png MASK.png OUTPUT.png\n", stderr)
    exit(2)
}

func loadImage(at path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

guard
    let sourceImage = loadImage(at: CommandLine.arguments[1]),
    let maskImage = loadImage(at: CommandLine.arguments[2])
else {
    fputs("Unable to load source or mask PNG.\n", stderr)
    exit(3)
}

let width = sourceImage.width
let height = sourceImage.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func rasterize(_ image: CGImage) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

guard var sourcePixels = rasterize(sourceImage), let maskPixels = rasterize(maskImage) else {
    fputs("Unable to rasterize source or mask PNG.\n", stderr)
    exit(4)
}

for index in 0..<(width * height) {
    let offset = index * bytesPerPixel
    let alpha = Int(maskPixels[offset + 3])
    sourcePixels[offset] = UInt8(Int(sourcePixels[offset]) * alpha / 255)
    sourcePixels[offset + 1] = UInt8(Int(sourcePixels[offset + 1]) * alpha / 255)
    sourcePixels[offset + 2] = UInt8(Int(sourcePixels[offset + 2]) * alpha / 255)
    sourcePixels[offset + 3] = UInt8(alpha)
}

guard
    let outputContext = CGContext(
        data: &sourcePixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ),
    let outputImage = outputContext.makeImage()
else {
    fputs("Unable to create output image.\n", stderr)
    exit(5)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create output PNG.\n", stderr)
    exit(6)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write output PNG.\n", stderr)
    exit(7)
}

print("Applied alpha mask at \(width)x\(height).")
