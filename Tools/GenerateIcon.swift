// Generates the Prism app icon at every required size.
// Run from the project root:  swift Tools/GenerateIcon.swift
// Output: Prism/Assets.xcassets/AppIcon.appiconset/

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let spectrum: [CGColor] = [
    rgb(1.00, 0.31, 0.34),
    rgb(1.00, 0.62, 0.24),
    rgb(1.00, 0.85, 0.28),
    rgb(0.36, 0.92, 0.52),
    rgb(0.30, 0.70, 1.00),
    rgb(0.67, 0.44, 1.00),
]

func drawBeam(_ ctx: CGContext, origin: CGPoint, angle: CGFloat,
              length: CGFloat, width: CGFloat, color: CGColor, alpha: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: angle)
    let rect = CGRect(x: 0, y: -width / 2, width: length, height: width)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
    ctx.setFillColor(color.copy(alpha: alpha) ?? color)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawSegment(_ ctx: CGContext, from: CGPoint, to: CGPoint,
                 width: CGFloat, color: CGColor, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(color.copy(alpha: alpha) ?? color)
    ctx.move(to: from)
    ctx.addLine(to: to)
    ctx.strokePath()
    ctx.restoreGState()
}

func makeIcon(_ pixels: Int) -> CGImage {
    let s = CGFloat(pixels)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Rounded tile.
    let margin = s * 0.085
    let tileRect = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = tileRect.width * 0.225
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tileRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Background gradient.
    let bgLocations: [CGFloat] = [0, 1]
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(0.15, 0.12, 0.27), rgb(0.04, 0.03, 0.07)] as CFArray,
                        locations: bgLocations)!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Soft glow behind the refracted light.
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(1, 1, 1, 0.20), rgb(1, 1, 1, 0)] as CFArray,
                          locations: bgLocations)!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: s * 0.60, y: s * 0.42), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.60, y: s * 0.42), endRadius: s * 0.44,
                           options: [])

    // Refracted spectrum fanning from the prism.
    let origin = CGPoint(x: s * 0.49, y: s * 0.52)
    let beamLength = s * 0.40
    let beamWidth = s * 0.040
    for (index, color) in spectrum.enumerated() {
        let degrees = -8.0 - Double(index) * 7.6
        let angle = CGFloat(degrees * .pi / 180)
        drawBeam(ctx, origin: origin, angle: angle, length: beamLength,
                 width: beamWidth * 2.6, color: color, alpha: 0.16)
        drawBeam(ctx, origin: origin, angle: angle, length: beamLength,
                 width: beamWidth, color: color, alpha: 1)
    }

    // Incoming white light beam.
    let beamStart = CGPoint(x: s * 0.11, y: s * 0.605)
    let beamEnd = CGPoint(x: s * 0.42, y: s * 0.55)
    drawSegment(ctx, from: beamStart, to: beamEnd, width: beamWidth * 2.4, color: rgb(1, 1, 1), alpha: 0.16)
    drawSegment(ctx, from: beamStart, to: beamEnd, width: beamWidth, color: rgb(1, 1, 1), alpha: 1)

    // The prism itself.
    let apex = CGPoint(x: s * 0.45, y: s * 0.685)
    let bottomLeft = CGPoint(x: s * 0.285, y: s * 0.355)
    let bottomRight = CGPoint(x: s * 0.62, y: s * 0.355)
    let triangle = CGMutablePath()
    triangle.move(to: apex)
    triangle.addLine(to: bottomRight)
    triangle.addLine(to: bottomLeft)
    triangle.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(triangle)
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(triangle)
    ctx.clip()
    let sheen = CGGradient(colorsSpace: space,
                           colors: [rgb(1, 1, 1), rgb(0.78, 0.80, 0.92)] as CFArray,
                           locations: bgLocations)!
    ctx.drawLinearGradient(sheen, start: apex,
                           end: CGPoint(x: (bottomLeft.x + bottomRight.x) / 2, y: bottomLeft.y),
                           options: [])
    ctx.restoreGState()

    ctx.addPath(triangle)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.5))
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(
        url, UTType.png.identifier as CFString, 1, nil
    ) else {
        fatalError("Could not create image destination at \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(path)")
    }
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = FileManager.default.currentDirectoryPath + "/Prism/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    writePNG(makeIcon(size), to: "\(outputDir)/icon_\(size).png")
    print("wrote icon_\(size).png")
}

let contentsJSON = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contentsJSON.write(toFile: "\(outputDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote Contents.json")
