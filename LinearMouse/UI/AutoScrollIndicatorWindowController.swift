// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

private let autoScrollIndicatorDiameter: CGFloat = 34
// Leave room around the disc so its shadow isn't clipped by the panel bounds.
private let autoScrollIndicatorMargin: CGFloat = 10
private let autoScrollIndicatorPanelSize = CGSize(
    width: autoScrollIndicatorDiameter + autoScrollIndicatorMargin * 2,
    height: autoScrollIndicatorDiameter + autoScrollIndicatorMargin * 2
)

final class AutoScrollIndicatorWindowController {
    private let glyphView = AutoScrollIndicatorGlyphView()

    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: autoScrollIndicatorPanelSize),
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
        panel.animationBehavior = .none
        panel.contentView = makeContentView()
        return panel
    }()

    private func makeContentView() -> NSView {
        let discFrame = CGRect(
            x: autoScrollIndicatorMargin,
            y: autoScrollIndicatorMargin,
            width: autoScrollIndicatorDiameter,
            height: autoScrollIndicatorDiameter
        )

        let container = NSView(frame: CGRect(origin: .zero, size: autoScrollIndicatorPanelSize))
        container.wantsLayer = true

        // The effect view clips to the circle, so the shadow lives on a separate layer.
        let shadowLayer = CALayer()
        shadowLayer.frame = discFrame
        shadowLayer.shadowPath = CGPath(ellipseIn: CGRect(origin: .zero, size: discFrame.size), transform: nil)
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.16
        shadowLayer.shadowRadius = 3
        shadowLayer.shadowOffset = CGSize(width: 0, height: -1)
        container.layer?.addSublayer(shadowLayer)

        // A plain HUD material reads consistently on SDR and HDR displays, unlike
        // Liquid Glass, whose refraction looks muddy without HDR headroom.
        let effect = NSVisualEffectView(frame: discFrame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .circleMask(diameter: autoScrollIndicatorDiameter)
        container.addSubview(effect)

        glyphView.frame = effect.bounds
        glyphView.autoresizingMask = [.width, .height]
        effect.addSubview(glyphView)

        return container
    }

    func show(at point: CGPoint) {
        let origin = CGPoint(
            x: point.x - autoScrollIndicatorPanelSize.width / 2,
            y: point.y - autoScrollIndicatorPanelSize.height / 2
        )
        window.setFrame(CGRect(origin: origin, size: autoScrollIndicatorPanelSize), display: false)
        glyphView.delta = .zero

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    func update(delta: CGVector) {
        glyphView.delta = delta
    }

    func hide() {
        // Hide immediately; a lingering HUD reads as if Auto Scroll were still active.
        window.alphaValue = 0
        window.orderOut(nil)
    }
}

private final class AutoScrollIndicatorGlyphView: NSView {
    var delta: CGVector = .zero {
        didSet {
            guard delta != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // A light tint keeps the glyphs legible whatever is behind the material.
        (isDark ? NSColor.black.withAlphaComponent(0.3) : NSColor.white.withAlphaComponent(0.3)).setFill()
        NSBezierPath(ovalIn: bounds).fill()

        let rim = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        (isDark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.1)).setStroke()
        rim.stroke()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let horizontalIntensity = intensity(for: delta.dx)
        let verticalIntensity = intensity(for: delta.dy)

        drawChevron(center: center, direction: .up, intensity: delta.dy > 0 ? verticalIntensity : 0)
        drawChevron(center: center, direction: .right, intensity: delta.dx > 0 ? horizontalIntensity : 0)
        drawChevron(center: center, direction: .down, intensity: delta.dy < 0 ? verticalIntensity : 0)
        drawChevron(center: center, direction: .left, intensity: delta.dx < 0 ? horizontalIntensity : 0)

        let dotRadius: CGFloat = 2
        let dot = NSBezierPath(ovalIn: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        NSColor.labelColor.withAlphaComponent(0.7).setFill()
        dot.fill()
    }

    private func intensity(for value: CGFloat) -> CGFloat {
        min(1, max(0, (abs(value) - 10) / 44))
    }

    private func drawChevron(center: CGPoint, direction: Direction, intensity: CGFloat) {
        let distance: CGFloat = 10.25
        let halfWidth: CGFloat = 3.75
        let depth: CGFloat = 3.125

        let (axis, normal): (CGVector, CGVector) = switch direction {
        case .up:
            (CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0))
        case .down:
            (CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0))
        case .right:
            (CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1))
        case .left:
            (CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1))
        }

        let tip = CGPoint(x: center.x + axis.dx * distance, y: center.y + axis.dy * distance)
        let base = CGPoint(x: tip.x - axis.dx * depth, y: tip.y - axis.dy * depth)

        let path = NSBezierPath()
        path.move(to: CGPoint(x: base.x + normal.dx * halfWidth, y: base.y + normal.dy * halfWidth))
        path.line(to: tip)
        path.line(to: CGPoint(x: base.x - normal.dx * halfWidth, y: base.y - normal.dy * halfWidth))
        path.lineWidth = 1.75
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let alpha = 0.25 + Double(intensity) * 0.7
        NSColor.labelColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private enum Direction {
        case up
        case right
        case down
        case left
    }
}

private extension NSImage {
    static func circleMask(diameter: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
