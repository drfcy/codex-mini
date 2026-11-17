import AppKit

let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func render(_ name: String, pixels: Int, to output: URL) throws {
    guard let image = NSImage(contentsOf: resources.appendingPathComponent(name + ".svg")),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("Cannot render icon")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output)
}

try render("MenuIcon", pixels: 36, to: resources.appendingPathComponent("MenuIcon.png"))
try render("AppIcon", pixels: 1024, to: resources.appendingPathComponent("AppIcon.png"))
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("codexmini-icons-" + UUID().uuidString)
let iconset = scratch.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
for size in [16, 32, 128, 256, 512] {
    try render("AppIcon", pixels: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render("AppIcon", pixels: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try tool.run()
tool.waitUntilExit()
guard tool.terminationStatus == 0 else { fatalError("Icon packaging failed") }
