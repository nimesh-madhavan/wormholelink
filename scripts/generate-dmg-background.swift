import AppKit
import Foundation

@main
struct GenerateDMGBackground {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            fputs("usage: generate-dmg-background <output-png-path>\n", stderr)
            exit(64)
        }

        let outputURL = URL(fileURLWithPath: arguments[1])
        let width = 720
        let height = 420
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "GenerateDMGBackground", code: 1)
        }

        bitmap.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw NSError(domain: "GenerateDMGBackground", code: 2)
        }

        NSGraphicsContext.current = context
        drawBackground(in: rect)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GenerateDMGBackground", code: 3)
        }

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL, options: .atomic)
    }

    private static func drawBackground(in rect: NSRect) {
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: rect).fill()

        let headerRect = NSRect(x: 90, y: 302, width: rect.width - 180, height: 72)
        drawTextBlock(in: headerRect)
        drawInstallPanel(in: NSRect(x: 414, y: 62, width: 250, height: 224))
    }

    private static func drawTextBlock(in rect: NSRect) {
        drawText(
            "Drag WormholeLink into Applications",
            rect: NSRect(x: rect.minX, y: rect.maxY - 34, width: rect.width, height: 34),
            font: NSFont.systemFont(ofSize: 28, weight: .regular),
            color: NSColor(calibratedRed: 0.23, green: 0.27, blue: 0.30, alpha: 0.98),
            shadowColor: nil
        )

        drawText(
            "Native macOS SSH tunnel manager",
            rect: NSRect(x: rect.minX, y: rect.minY + 6, width: rect.width, height: 22),
            font: NSFont.systemFont(ofSize: 16, weight: .medium),
            color: NSColor(calibratedRed: 0.43, green: 0.49, blue: 0.55, alpha: 0.95),
            shadowColor: nil
        )
    }

    private static func drawInstallPanel(in rect: NSRect) {
        let fillColor = NSColor(calibratedRed: 0.91, green: 0.95, blue: 0.99, alpha: 1)
        let borderColor = NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.96, alpha: 1)

        let path = NSBezierPath()
        let notchMidY = rect.midY
        let notchDepth: CGFloat = 34
        let radius: CGFloat = 18

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.curve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: CGPoint(x: rect.maxX - radius * 0.3, y: rect.minY),
            controlPoint2: CGPoint(x: rect.maxX, y: rect.minY + radius * 0.3)
        )
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.curve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            controlPoint1: CGPoint(x: rect.maxX, y: rect.maxY - radius * 0.3),
            controlPoint2: CGPoint(x: rect.maxX - radius * 0.3, y: rect.maxY)
        )
        path.line(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.curve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            controlPoint1: CGPoint(x: rect.minX + radius * 0.3, y: rect.maxY),
            controlPoint2: CGPoint(x: rect.minX, y: rect.maxY - radius * 0.3)
        )
        path.line(to: CGPoint(x: rect.minX, y: notchMidY + 28))
        path.line(to: CGPoint(x: rect.minX + notchDepth, y: notchMidY))
        path.line(to: CGPoint(x: rect.minX, y: notchMidY - 28))
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.curve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: CGPoint(x: rect.minX, y: rect.minY + radius * 0.3),
            controlPoint2: CGPoint(x: rect.minX + radius * 0.3, y: rect.minY)
        )
        path.close()

        fillColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, shadowColor: NSColor?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        if let shadowColor {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            shadow.shadowColor = shadowColor
            attributes[.shadow] = shadow
        }

        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

}