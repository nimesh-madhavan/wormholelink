import AppKit

enum WormholeIcon {
    static func applicationIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: image.size)
        let background = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
        NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.16, alpha: 1).setFill()
        background.fill()

        drawWormhole(in: rect, colorMode: .fullColor, activeCount: 1, animationFrame: 0, isConnecting: false)

        image.unlockFocus()
        return image
    }

    static func statusBarImage(activeCount: Int, isConnecting: Bool, animationFrame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = true
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        drawWormhole(in: rect, colorMode: .template, activeCount: activeCount, animationFrame: animationFrame, isConnecting: isConnecting)

        image.unlockFocus()
        return image
    }

    private enum ColorMode {
        case template
        case fullColor
    }

    private static func drawWormhole(in rect: NSRect, colorMode: ColorMode, activeCount: Int, animationFrame: Int, isConnecting: Bool) {
        let strokeColor: NSColor
        let coreColor: NSColor
        let glowColor: NSColor
        let badgeColor: NSColor

        switch colorMode {
        case .template:
            strokeColor = .labelColor
            coreColor = .labelColor
            glowColor = .labelColor
            badgeColor = .labelColor
        case .fullColor:
            strokeColor = NSColor(calibratedWhite: 0.97, alpha: 0.97)
            coreColor = NSColor(calibratedRed: 0.70, green: 0.92, blue: 1.0, alpha: 0.98)
            glowColor = NSColor(calibratedRed: 0.42, green: 0.82, blue: 1.0, alpha: 0.68)
            badgeColor = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.28, alpha: 1)
        }

        let normalizedFrame = CGFloat(animationFrame % 12) / 11.0
        let pulseScale: CGFloat = isConnecting ? (1.0 + 0.08 * sin(normalizedFrame * .pi * 2)) : 1.0
        let portalWidth = rect.width * 0.21 * pulseScale
        let portalHeight = rect.height * 0.63 * pulseScale
        let leftPortal = NSRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.midY - portalHeight / 2,
            width: portalWidth,
            height: portalHeight
        )
        let rightPortal = NSRect(
            x: rect.maxX - rect.width * 0.08 - portalWidth,
            y: rect.midY - portalHeight / 2,
            width: portalWidth,
            height: portalHeight
        )

        let bridge = bridgePath(in: rect, leftPortal: leftPortal, rightPortal: rightPortal)

        if colorMode == .fullColor {
            NSShadow.wormholeBlur(radius: rect.width * 0.08, color: glowColor.withAlphaComponent(0.55)) {
                glowColor.withAlphaComponent(0.30).setFill()
                bridge.fill()
            }

            if let bridgeGradient = NSGradient(colors: [
                coreColor.withAlphaComponent(0.95),
                strokeColor.withAlphaComponent(0.92),
                coreColor.withAlphaComponent(0.95)
            ]) {
                bridgeGradient.draw(in: bridge, angle: 0)
            }
        } else {
            strokeColor.withAlphaComponent(0.95).setStroke()
            bridge.lineWidth = max(1.2, rect.width * 0.06)
            bridge.stroke()
        }

        drawPortal(in: leftPortal, colorMode: colorMode, strokeColor: strokeColor, coreColor: coreColor, glowColor: glowColor)
        drawPortal(in: rightPortal, colorMode: colorMode, strokeColor: strokeColor, coreColor: coreColor, glowColor: glowColor)

        if activeCount > 0 || isConnecting {
            drawConnectionBeam(in: rect, colorMode: colorMode, strokeColor: strokeColor, glowColor: glowColor, animationFrame: animationFrame, isConnecting: isConnecting)
        }

        let centerOrbRect = NSRect(
            x: rect.midX - rect.width * 0.04,
            y: rect.midY - rect.width * 0.04,
            width: rect.width * 0.08,
            height: rect.width * 0.08
        )
        let centerOrb = NSBezierPath(ovalIn: centerOrbRect)
        if colorMode == .fullColor {
            NSColor(calibratedRed: 0.09, green: 0.56, blue: 0.93, alpha: 0.95).setFill()
            NSShadow.wormholeBlur(radius: rect.width * 0.035, color: glowColor.withAlphaComponent(0.62)) {
                centerOrb.fill()
            }
        } else {
            strokeColor.setFill()
            centerOrb.fill()
        }

        if activeCount > 1 {
            let badgeRect = NSRect(
                x: rect.maxX - rect.width * 0.34,
                y: rect.minY + rect.height * 0.02,
                width: rect.width * 0.26,
                height: rect.width * 0.26
            )
            let badge = NSBezierPath(ovalIn: badgeRect)
            badgeColor.setFill()
            badge.fill()
        }
    }

    private static func bridgePath(in rect: NSRect, leftPortal: NSRect, rightPortal: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: leftPortal.midX, y: leftPortal.maxY - leftPortal.height * 0.12))
        path.curve(
            to: CGPoint(x: rightPortal.midX, y: rightPortal.maxY - rightPortal.height * 0.12),
            controlPoint1: CGPoint(x: rect.midX - rect.width * 0.14, y: rect.midY + rect.height * 0.10),
            controlPoint2: CGPoint(x: rect.midX + rect.width * 0.14, y: rect.midY + rect.height * 0.10)
        )
        path.line(to: CGPoint(x: rightPortal.midX, y: rightPortal.minY + rightPortal.height * 0.12))
        path.curve(
            to: CGPoint(x: leftPortal.midX, y: leftPortal.minY + leftPortal.height * 0.12),
            controlPoint1: CGPoint(x: rect.midX + rect.width * 0.14, y: rect.midY - rect.height * 0.10),
            controlPoint2: CGPoint(x: rect.midX - rect.width * 0.14, y: rect.midY - rect.height * 0.10)
        )
        path.close()
        return path
    }

    private static func drawPortal(in rect: NSRect, colorMode: ColorMode, strokeColor: NSColor, coreColor: NSColor, glowColor: NSColor) {
        let outer = NSBezierPath(ovalIn: rect)
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.16))

        if colorMode == .fullColor {
            NSShadow.wormholeBlur(radius: rect.width * 0.30, color: glowColor.withAlphaComponent(0.72)) {
                glowColor.withAlphaComponent(0.32).setFill()
                outer.fill()
            }

            if let gradient = NSGradient(colors: [
                strokeColor.withAlphaComponent(0.98),
                coreColor.withAlphaComponent(0.97),
                NSColor(calibratedRed: 0.56, green: 0.88, blue: 1.0, alpha: 0.9)
            ]) {
                gradient.draw(in: outer, relativeCenterPosition: .zero)
            }

            NSColor.white.withAlphaComponent(0.82).setStroke()
            outer.lineWidth = rect.width * 0.08
            outer.stroke()

            let ripple = NSBezierPath()
            ripple.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.midY))
            ripple.curve(
                to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.midY),
                controlPoint1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.12),
                controlPoint2: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.minY + rect.height * 0.12)
            )
            ripple.lineWidth = max(1.3, rect.width * 0.07)
            NSColor.white.withAlphaComponent(0.68).setStroke()
            ripple.stroke()

            NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.24, alpha: 0.34).setFill()
            inner.fill()
        } else {
            outer.lineWidth = max(1.1, rect.width * 0.16)
            strokeColor.setStroke()
            outer.stroke()

            inner.lineWidth = max(0.8, rect.width * 0.09)
            strokeColor.withAlphaComponent(0.82).setStroke()
            inner.stroke()
        }
    }

    private static func drawConnectionBeam(in rect: NSRect, colorMode: ColorMode, strokeColor: NSColor, glowColor: NSColor, animationFrame: Int, isConnecting: Bool) {
        let beamY = rect.midY
        let sweep = CGFloat(animationFrame % 12) / 11.0
        let inset = rect.width * 0.10
        let beamStartX = rect.minX + inset
        let beamEndX = rect.maxX - inset

        let beam = NSBezierPath()
        beam.move(to: CGPoint(x: beamStartX, y: beamY))
        beam.line(to: CGPoint(x: beamEndX, y: beamY))
        beam.lineWidth = max(1.0, rect.width * 0.085)
        beam.lineCapStyle = .round

        if colorMode == .fullColor {
            NSColor.white.withAlphaComponent(0.82).setStroke()
            beam.stroke()
            return
        }

        strokeColor.withAlphaComponent(isConnecting ? 0.65 : 0.95).setStroke()
        beam.stroke()

        if isConnecting {
            let headX = beamStartX + (beamEndX - beamStartX) * sweep
            let headRect = NSRect(x: headX - rect.width * 0.065, y: beamY - rect.width * 0.065, width: rect.width * 0.13, height: rect.width * 0.13)
            let head = NSBezierPath(ovalIn: headRect)
            glowColor.withAlphaComponent(0.95).setFill()
            head.fill()
        }
    }
}

private extension NSShadow {
    static func wormholeBlur(radius: CGFloat, color: NSColor, offset: CGSize = .zero, drawing: () -> Void) {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = radius
        shadow.shadowColor = color
        shadow.shadowOffset = offset
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        drawing()
        NSGraphicsContext.restoreGraphicsState()
    }
}