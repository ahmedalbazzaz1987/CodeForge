// Draws the app icon into an .iconset folder: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let tile = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.30, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.09, blue: 0.27, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    let text = "</>" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: tile.height * 0.34, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: tile.midX - textSize.width / 2, y: tile.midY - textSize.height / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
