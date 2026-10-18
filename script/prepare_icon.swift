import AppKit
import ImageIO
import UniformTypeIdentifiers

// Packaging only: keep the Magnific master intact, add the macOS tile mask,
// and produce the exact PNG sizes consumed by iconutil.
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: prepare_icon <master-image> <Assets-directory>\n", stderr)
    exit(2)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width >= 1024, image.height >= 1024, image.width == image.height else {
    fputs("Icon master must be square and at least 1024 pixels.\n", stderr)
    exit(1)
}
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func canvas(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func writePNG(_ image: CGImage, _ url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconPackaging", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "IconPackaging", code: 2) }
}
let context = canvas(1024)
let tile = CGRect(x: 64, y: 64, width: 896, height: 896)
let path = CGPath(roundedRect: tile, cornerWidth: 198, cornerHeight: 198, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.22))
context.addPath(path); context.setFillColor(CGColor(gray: 0.05, alpha: 1)); context.fillPath()
context.restoreGState()
context.addPath(path); context.clip()
context.interpolationQuality = .high
context.draw(image, in: tile)
guard let master = context.makeImage() else { fatalError("Could not render icon") }
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try writePNG(master, assets.appendingPathComponent("AppIcon.png"))
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let resized = canvas(pixels)
        resized.interpolationQuality = .high
        resized.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(resized.makeImage()!, iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
print("Prepared 1024px master and 10 iconset images from the unchanged Magnific source.")
