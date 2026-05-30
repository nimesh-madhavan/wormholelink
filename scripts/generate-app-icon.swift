import AppKit
import Foundation

@main
struct GenerateAppIcon {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            fputs("usage: swift WormholeIcon.swift generate-app-icon.swift <output-icns-path>\n", stderr)
            exit(64)
        }

        let outputURL = URL(fileURLWithPath: arguments[1])
        let fileManager = FileManager.default
        let iconsetURL = outputURL.deletingPathExtension().appendingPathExtension("iconset")

        try? fileManager.removeItem(at: iconsetURL)
        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        let iconSizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
            ("icon_16x16.png", 16, 1),
            ("icon_16x16@2x.png", 16, 2),
            ("icon_32x32.png", 32, 1),
            ("icon_32x32@2x.png", 32, 2),
            ("icon_128x128.png", 128, 1),
            ("icon_128x128@2x.png", 128, 2),
            ("icon_256x256.png", 256, 1),
            ("icon_256x256@2x.png", 256, 2),
            ("icon_512x512.png", 512, 1),
            ("icon_512x512@2x.png", 512, 2),
        ]

        for iconSize in iconSizes {
            let pixelSize = iconSize.points * iconSize.scale
            let image = WormholeIcon.applicationIcon(size: pixelSize)
            let imageURL = iconsetURL.appendingPathComponent(iconSize.name)
            try writePNG(for: image, to: imageURL, pixelSize: Int(pixelSize))
        }

        try? fileManager.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GenerateAppIcon", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"
            ])
        }

        try? fileManager.removeItem(at: iconsetURL)
    }

    private static func writePNG(for image: NSImage, to url: URL, pixelSize: Int) throws {
        let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create bitmap representation"
            ])
        }

        bitmap.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw NSError(domain: "GenerateAppIcon", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create graphics context"
            ])
        }

        NSGraphicsContext.current = context
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GenerateAppIcon", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode PNG"
            ])
        }

        try data.write(to: url)
    }
}