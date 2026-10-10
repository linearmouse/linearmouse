// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

// Portions adapted from PermissionFlow, Copyright (c) 2026 小弟调调.
// Full MIT permission notice: ThirdPartyNotices/PermissionFlow.txt.
// Upstream sources:
// https://github.com/jaywcjlove/PermissionFlow/blob/cb96db4bfd2342e8d8c56f2a7d51ca65b8aed6e2/Sources/PermissionFlow/UI/FloatingDropPanel.swift
// https://github.com/jaywcjlove/PermissionFlow/blob/cb96db4bfd2342e8d8c56f2a7d51ca65b8aed6e2/Sources/PermissionFlow/UI/PermissionFlowPanelView.swift

final class PermissionDragPanel: NSPanel {
    private var contentWidth: CGFloat = 420
    private var contentHeight: CGFloat = 160
    private var launchSource: CGRect?
    private var launchTime: TimeInterval?
    private(set) var isDraggingApp = false
    var onCancel: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.fullScreenAuxiliary]
        render(width: contentWidth)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func prepare(from point: CGPoint) {
        launchSource = CGRect(x: point.x - 80, y: point.y - 40, width: 160, height: 80)
        launchTime = nil
    }

    func follow(_ settingsFrame: CGRect) {
        guard let screen = NSScreen.screens.max(by: {
            Self.area($0.frame.intersection(settingsFrame)) < Self.area($1.frame.intersection(settingsFrame))
        }) else {
            return
        }
        let width = min(max(260, settingsFrame.width - 230), screen.visibleFrame.width - 24)
        if !isDraggingApp, abs(width - contentWidth) > 0.5 {
            render(width: width)
        }
        let target = PermissionGuidePlacement.frame(
            size: CGSize(width: contentWidth, height: contentHeight), below: settingsFrame, within: screen.visibleFrame
        )
        var destination = target
        if let source = launchSource, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let now = ProcessInfo.processInfo.systemUptime
            let start = launchTime ?? now
            launchTime = start
            let progress = min(1, (now - start) / 0.28)
            let eased = CGFloat(1 - pow(1 - progress, 3))
            destination = CGRect(
                x: source.minX + (target.minX - source.minX) * eased,
                y: source.minY + (target.minY - source.minY) * eased,
                width: source.width + (target.width - source.width) * eased,
                height: source.height + (target.height - source.height) * eased
            )
            alphaValue = eased
            if progress == 1 {
                launchSource = nil
            }
        } else {
            launchSource = nil
            alphaValue = isDraggingApp ? 0.72 : 1
        }
        if frame != destination {
            setFrame(destination, display: true)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontmost == "com.apple.systempreferences" || frontmost == Bundle.main.bundleIdentifier {
            if !isVisible, !isDraggingApp {
                orderFrontRegardless()
            }
        } else if !isDraggingApp {
            orderOut(nil)
        }
    }

    private func render(width: CGFloat) {
        contentWidth = width
        let view = NSHostingView(rootView: PermissionDragPanelView(
            width: width,
            onDragging: { [weak self] in self?.setDragging($0) },
            onCancel: { [weak self] in self?.onCancel() }
        ))
        contentHeight = view.fittingSize.height
        if #available(macOS 13.3, *) {
            view.sizingOptions = []
        }
        contentView = view
    }

    private func setDragging(_ dragging: Bool) {
        isDraggingApp = dragging
        // Keep the guide in place so dragging over it cannot expose windows underneath.
        alphaValue = dragging ? 0.72 : 1
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

struct PermissionDragPanelView: View {
    var width: CGFloat = 420
    var onDragging: (Bool) -> Void = { _ in }
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                directionIcon
                    .foregroundColor(.accentColor)
                    .accessibility(hidden: true)
                Text("Drag the LinearMouse icon below into the list above.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 28)
            PermissionAppDragSource(onDragging: onDragging)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .contextMenu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
        }
        .padding(16)
        .frame(width: width)
        .background(PanelMaterial())
        .cornerRadius(16)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(closeButton.padding(10), alignment: .topTrailing)
    }

    @ViewBuilder private var directionIcon: some View {
        if #available(macOS 11, *) {
            Image(systemName: "arrow.up")
        } else {
            Text(verbatim: "↑")
        }
    }

    private var closeButton: some View {
        Button(action: onCancel) {
            Group {
                if #available(macOS 11, *) {
                    Image(systemName: "xmark.circle.fill")
                } else {
                    Text(verbatim: "×")
                }
            }
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibility(label: Text("Cancel"))
    }
}

private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
