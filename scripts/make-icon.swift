import AppKit

// Convert the committed generated artwork into the standard macOS icon sizes.
// Image generation is a design-time step; building and running the app stay offline.
let source = URL(fileURLWithPath: "Resources/AppIcon-dark.png")
guard let image = NSImage(contentsOf: source),
      let data = try? Data(contentsOf: source),
      let sourceBitmap = NSBitmapImageRep(data: data),
      sourceBitmap.pixelsWide == sourceBitmap.pixelsHigh,
      sourceBitmap.pixelsWide >= 1024,
      sourceBitmap.hasAlpha else {
    fatalError("Expected a square, transparent PNG of at least 1024 pixels at \(source.path)")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
