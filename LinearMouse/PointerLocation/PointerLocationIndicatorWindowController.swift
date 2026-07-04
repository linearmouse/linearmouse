// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import QuartzCore

private let pointerLocationIndicatorSize = CGSize(width: 180, height: 180)
private let pointerLocationIndicatorDuration: TimeInterval = 0.8

final class PointerLocationIndicatorWindowController {
    private var animationTimer: Timer?
    private var animationStartTime: CFTimeInterval?

    private lazy var indicatorView = PointerLocationIndicatorView(
        frame: CGRect(origin: .zero, size: pointerLocationIndicatorSize)
    )

    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: pointerLocationIndicatorSize),
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
        panel.contentView = indicatorView
        return panel
    }()

    deinit {
        animationTimer?.invalidate()
    }

    func show(at point: CGPoint) {
        let origin = CGPoint(
            x: point.x - pointerLocationIndicatorSize.width / 2,
            y: point.y - pointerLocationIndicatorSize.height / 2
        )
        window.setFrame(CGRect(origin: origin, size: pointerLocationIndicatorSize), display: true)
        window.orderFrontRegardless()
        startAnimation()
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationStartTime = CACurrentMediaTime()
        indicatorView.progress = 0

        let framesPerSecond: Int
        if #available(macOS 12.0, *) {
            framesPerSecond = min(NSScreen.main?.maximumFramesPerSecond ?? 60, 120)
        } else {
            framesPerSecond = 60
        }
        let timer = Timer(timeInterval: 1.0 / TimeInterval(framesPerSecond), repeats: true) { [weak self] timer in
            self?.updateAnimation(timer)
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateAnimation(_ timer: Timer) {
        guard let animationStartTime else {
            timer.invalidate()
            return
        }

        let elapsed = CACurrentMediaTime() - animationStartTime
        let progress = min(1, elapsed / pointerLocationIndicatorDuration)
        indicatorView.progress = progress

        if progress >= 1 {
            timer.invalidate()
            animationTimer = nil
            window.orderOut(nil)
        }
    }
}

private final class PointerLocationIndicatorView: NSView {
    var progress: TimeInterval = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let bounds = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let pulseProgress = reducedMotion ? 1 : progress
        let fadeProgress = max(0, (progress - 0.75) / 0.25)
        let alpha = CGFloat(1 - fadeProgress)
        let easedPulse = easeOutCubic(CGFloat(pulseProgress))
        let radius = reducedMotion ? CGFloat(26) : CGFloat(76 - 52 * easedPulse)

        context.setShouldAntialias(true)
        drawRing(
            center: center,
            radius: radius,
            backingLineWidth: 5,
            lineWidth: 2,
            alpha: alpha
        )
    }

    private func drawRing(
        center: CGPoint,
        radius: CGFloat,
        backingLineWidth: CGFloat,
        lineWidth: CGFloat,
        alpha: CGFloat
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = NSBezierPath(ovalIn: rect)
        NSColor.white.withAlphaComponent(0.75 * alpha).setStroke()
        path.lineWidth = backingLineWidth
        path.stroke()

        NSColor.black.withAlphaComponent(0.9 * alpha).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func easeOutCubic(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - value, 3)
    }
}
