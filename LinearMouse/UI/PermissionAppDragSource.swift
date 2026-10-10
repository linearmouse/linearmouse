// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

// Portions adapted from PermissionFlow, Copyright (c) 2026 小弟调调.
// Full MIT permission notice: ThirdPartyNotices/PermissionFlow.txt.
// Upstream sources:
// https://github.com/jaywcjlove/PermissionFlow/blob/cb96db4bfd2342e8d8c56f2a7d51ca65b8aed6e2/Sources/PermissionFlow/UI/AppDropArea.swift

/// Supplies the running app's actual file URL, as Finder does when dragging an application.
struct PermissionAppDragSource: NSViewRepresentable {
    var onDragging: (Bool) -> Void = { _ in }

    func makeNSView(context _: Context) -> AppItemView {
        let view = AppItemView()
        view.onDragging = onDragging
        return view
    }

    func updateNSView(_ view: AppItemView, context _: Context) {
        view.onDragging = onDragging
    }

    final class AppItemView: NSView, NSDraggingSource {
        private let appURL = Bundle.main.bundleURL
        private var mouseDownPoint: NSPoint?
        var onDragging: (Bool) -> Void = { _ in }

        init() {
            super.init(frame: .zero)
            let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
            icon.imageScaling = .scaleProportionallyUpOrDown
            let label = NSTextField(labelWithString: "LinearMouse")
            label.font = .systemFont(ofSize: 14)
            for view in [icon, label] {
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 32),
                icon.heightAnchor.constraint(equalToConstant: 32),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
            ])
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
            setAccessibilityLabel("LinearMouse")
            setAccessibilityHelp(NSLocalizedString(
                "Drag the LinearMouse icon below into the list above.", comment: "Permission setup drag hint"
            ))
        }

        required init?(coder _: NSCoder) {
            nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = event.locationInWindow
        }

        override func mouseUp(with _: NSEvent) {
            mouseDownPoint = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin = mouseDownPoint,
                  hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 4
            else {
                return
            }
            guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
                return
            }
            cacheDisplay(in: bounds, to: bitmap)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)
            mouseDownPoint = nil
            let writer = NSPasteboardItem()
            writer.setString(appURL.absoluteString, forType: .fileURL)
            // Older privacy panes also accept Finder's legacy file-list representation.
            writer.setPropertyList([appURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.draggingFrame = bounds
            let previewFrame = NSRect(origin: .zero, size: bounds.size)
            // The convenience setter marks the entire row as an icon, which AppKit can shrink
            // when arranging file drags. Keep this full-size preview as a custom component.
            item.imageComponentsProvider = {
                let component = NSDraggingImageComponent(key: .init(rawValue: "LinearMouse.permissionRow"))
                component.contents = image
                component.frame = previewFrame
                return [component]
            }
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.draggingFormation = .none
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_: NSDraggingSession, willBeginAt _: NSPoint) {
            onDragging(true)
        }

        func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
            onDragging(false)
        }

        func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for _: NSDraggingSession) -> Bool {
            true
        }
    }
}
