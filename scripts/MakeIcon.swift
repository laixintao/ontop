// Rebuild with: xcrun swift scripts/MakeIcon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/OnTop.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
        let background = NSBezierPath(roundedRect: rect, xRadius: 195, yRadius: 195)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.25, blue: 0.68, alpha: 1),
                                  ending: NSColor(srgbRed: 0.40, green: 0.51, blue: 0.98, alpha: 1))!
        gradient.draw(in: background, angle: 70)
        let window = NSBezierPath(roundedRect: NSRect(x: 235, y: 252, width: 554, height: 520), xRadius: 48, yRadius: 48)
        NSColor.white.withAlphaComponent(0.30).setStroke()
        window.lineWidth = 23
        window.stroke()
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: 247, y: 656))
        bar.line(to: NSPoint(x: 777, y: 656))
        bar.lineWidth = 19
        bar.stroke()
        let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(paletteColors: [.white]))!
        pin.draw(in: NSRect(x: 365, y: 340, width: 294, height: 366))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(filename))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("OnTop/Resources/OnTop.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }

