// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

private let autoScrollIndicatorSize = CGSize(width: 48, height: 48)

final class AutoScrollIndicatorWindowController {
    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: autoScrollIndicatorSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = AutoScrollIndicatorView(frame: CGRect(origin: .zero, size: autoScrollIndicatorSize))
        return panel
    }()

    func show(at point: CGPoint) {
        let origin = CGPoint(
            x: point.x - autoScrollIndicatorSize.width / 2,
            y: point.y - autoScrollIndicatorSize.height / 2
        )
        window.setFrame(CGRect(origin: origin, size: autoScrollIndicatorSize), display: true)
        window.orderFrontRegardless()
    }

    func update(delta: CGVector) {
        (window.contentView as? AutoScrollIndicatorView)?.delta = delta
    }

    func hide() {
        window.orderOut(nil)
    }
}

private final class AutoScrollIndicatorView: NSView {
    var delta: CGVector = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds
        let circleRect = bounds.insetBy(dx: 4, dy: 4)
        let ringPath = NSBezierPath(ovalIn: circleRect)

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 10,
                color: NSColor.black.withAlphaComponent(0.18).cgColor
            )

            let gradient = NSGradient(
                colors: [
                    NSColor(white: 1.0, alpha: 0.97),
                    NSColor(white: 0.93, alpha: 0.95)
                ]
            )
            gradient?.draw(in: ringPath, angle: 90)
            context.restoreGState()
        }

        NSColor(white: 0.12, alpha: 0.48).setStroke()
        ringPath.lineWidth = 1
        ringPath.stroke()

        let innerRingPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 1.5, dy: 1.5))
        NSColor.white.withAlphaComponent(0.45).setStroke()
        innerRingPath.lineWidth = 1
        innerRingPath.stroke()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let horizontalIntensity = CGFloat(min(1, max(0, (abs(delta.dx) - 10) / 44)))
        let verticalIntensity = CGFloat(min(1, max(0, (abs(delta.dy) - 10) / 44)))

        drawArrow(
            at: CGPoint(x: center.x, y: bounds.maxY - 13),
            direction: .up,
            intensity: delta.dy > 0 ? verticalIntensity : 0
        )
        drawArrow(
            at: CGPoint(x: bounds.maxX - 13, y: center.y),
            direction: .right,
            intensity: delta.dx > 0 ? horizontalIntensity : 0
        )
        drawArrow(
            at: CGPoint(x: center.x, y: bounds.minY + 13),
            direction: .down,
            intensity: delta.dy < 0 ? verticalIntensity : 0
        )
        drawArrow(
            at: CGPoint(x: bounds.minX + 13, y: center.y),
            direction: .left,
            intensity: delta.dx < 0 ? horizontalIntensity : 0
        )

        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: center.x, y: bounds.minY + 11))
        crosshair.line(to: CGPoint(x: center.x, y: bounds.maxY - 11))
        crosshair.move(to: CGPoint(x: bounds.minX + 11, y: center.y))
        crosshair.line(to: CGPoint(x: bounds.maxX - 11, y: center.y))
        NSColor(white: 0.1, alpha: 0.14).setStroke()
        crosshair.lineWidth = 1
        crosshair.stroke()

        let centerShadowRect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        let centerShadowPath = NSBezierPath(ovalIn: centerShadowRect)
        NSColor.black.withAlphaComponent(0.14).setFill()
        centerShadowPath.fill()

        let dotRect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor(white: 0.07, alpha: 0.96).setFill()
        dotPath.fill()

        let highlightRect = CGRect(x: center.x - 1.5, y: center.y + 1, width: 3, height: 2)
        let highlightPath = NSBezierPath(ovalIn: highlightRect)
        NSColor.white.withAlphaComponent(0.28).setFill()
        highlightPath.fill()
    }

    private func drawArrow(at center: CGPoint, direction: Direction, intensity: CGFloat) {
        let path = NSBezierPath()

        switch direction {
        case .up:
            path.move(to: CGPoint(x: center.x, y: center.y + 6))
            path.line(to: CGPoint(x: center.x - 4.5, y: center.y - 3))
            path.line(to: CGPoint(x: center.x + 4.5, y: center.y - 3))
        case .right:
            path.move(to: CGPoint(x: center.x + 6, y: center.y))
            path.line(to: CGPoint(x: center.x - 3, y: center.y + 4.5))
            path.line(to: CGPoint(x: center.x - 3, y: center.y - 4.5))
        case .down:
            path.move(to: CGPoint(x: center.x, y: center.y - 6))
            path.line(to: CGPoint(x: center.x - 4.5, y: center.y + 3))
            path.line(to: CGPoint(x: center.x + 4.5, y: center.y + 3))
        case .left:
            path.move(to: CGPoint(x: center.x - 6, y: center.y))
            path.line(to: CGPoint(x: center.x + 3, y: center.y + 4.5))
            path.line(to: CGPoint(x: center.x + 3, y: center.y - 4.5))
        }

        path.close()

        let alpha = 0.26 + Double(intensity) * 0.68
        NSColor(white: 0.04, alpha: alpha).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.18 + Double(intensity) * 0.12).setStroke()
        path.lineWidth = 0.7
        path.stroke()
    }

    private enum Direction {
        case up
        case right
        case down
        case left
    }
}
