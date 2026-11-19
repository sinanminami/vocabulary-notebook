import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: clean_icon_alpha.swift INPUT.png OUTPUT.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Unable to load input PNG.\n", stderr)
    exit(3)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create bitmap context.\n", stderr)
    exit(4)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

let pixelCount = width * height
let alphaThreshold: UInt8 = 12
var visited = [Bool](repeating: false, count: pixelCount)
var largestComponent: [Int] = []

func alpha(at index: Int) -> UInt8 {
    pixels[index * bytesPerPixel + 3]
}

for start in 0..<pixelCount where !visited[start] && alpha(at: start) >= alphaThreshold {
    visited[start] = true
    var component = [start]
    var cursor = 0

    while cursor < component.count {
        let index = component[cursor]
        cursor += 1
        let x = index % width
        let y = index / width

        let neighbours = [
            (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
            (x - 1, y - 1), (x + 1, y - 1),
            (x - 1, y + 1), (x + 1, y + 1),
        ]

        for (nextX, nextY) in neighbours
        where nextX >= 0 && nextX < width && nextY >= 0 && nextY < height {
            let next = nextY * width + nextX
            if !visited[next] && alpha(at: next) >= alphaThreshold {
                visited[next] = true
                component.append(next)
            }
        }
    }

    if component.count > largestComponent.count {
        largestComponent = component
    }
}

guard !largestComponent.isEmpty else {
    fputs("No foreground component found.\n", stderr)
    exit(5)
}

var keep = [Bool](repeating: false, count: pixelCount)
for index in largestComponent {
    let x = index % width
    let y = index / width
    for offsetY in -2...2 {
        for offsetX in -2...2 {
            let nextX = x + offsetX
            let nextY = y + offsetY
            if nextX >= 0 && nextX < width && nextY >= 0 && nextY < height {
                keep[nextY * width + nextX] = true
            }
        }
    }
}

for index in 0..<pixelCount where !keep[index] {
    let offset = index * bytesPerPixel
    pixels[offset] = 0
    pixels[offset + 1] = 0
    pixels[offset + 2] = 0
    pixels[offset + 3] = 0
}

guard
    let cleanedImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("Unable to create output PNG.\n", stderr)
    exit(6)
}

CGImageDestinationAddImage(destination, cleanedImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write output PNG.\n", stderr)
    exit(7)
}

print("Kept largest alpha component: \(largestComponent.count) pixels")
