// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

// https://gist.github.com/marcprux/afd2f80baa5b6d60865182a828e83586

/// Alignment guide for aligning a text field in a `Form`.
/// Thanks for Jim Dovey  https://developer.apple.com/forums/thread/126268
extension HorizontalAlignment {
    private enum ControlAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }

    static let controlAlignment = HorizontalAlignment(ControlAlignment.self)
}

public extension View {
    /// Attaches a label to this view for laying out in a `Form`
    /// - Parameter view: the label view to use
    /// - Returns: an `HStack` with an alignment guide for placing in a form
    func formLabel<V: View>(_ view: V) -> some View {
        HStack {
            view
            self
                .alignmentGuide(.controlAlignment) { $0[.leading] }
        }
        .alignmentGuide(.leading) { $0[.controlAlignment] }
    }
}

extension View {
    func asDefaultAction() -> some View {
        if #available(macOS 11, *) {
            return keyboardShortcut(.defaultAction)
        }
        return self
    }

    func asCancelAction() -> some View {
        if #available(macOS 11, *) {
            return keyboardShortcut(.cancelAction)
        }
        return self
    }

    func sheetPrimaryActionStyle() -> some View {
        modifier(SheetActionButtonModifier(kind: .primary))
    }

    func sheetSecondaryActionStyle() -> some View {
        modifier(SheetActionButtonModifier(kind: .secondary))
    }

    func sheetDestructiveActionStyle() -> some View {
        modifier(SheetActionButtonModifier(kind: .destructive))
    }
}

private enum SheetActionButtonKind {
    case primary
    case secondary
    case destructive
}

private struct SheetActionButtonModifier: ViewModifier {
    let kind: SheetActionButtonKind

    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            if kind == .primary {
                shapedContent(styledContent(content))
                    .buttonStyle(.borderedProminent)
            } else {
                shapedContent(styledContent(content))
                    .buttonStyle(.bordered)
            }
        } else {
            legacyStyledContent(content)
        }
    }

    private func styledContent(_ content: Content) -> some View {
        let base = sizeAdjustedContent(content)

        if #available(macOS 12.0, *), kind == .destructive {
            return AnyView(base.tint(.red))
        }
        return AnyView(base)
    }

    private func shapedContent(_ content: some View) -> some View {
        if #available(macOS 14.0, *) {
            return AnyView(content.buttonBorderShape(.capsule))
        } else {
            return AnyView(content)
        }
    }

    private func legacyStyledContent(_ content: Content) -> some View {
        let base = sizeAdjustedContent(content)

        if kind == .destructive {
            return AnyView(base.foregroundColor(.red))
        }
        return AnyView(base)
    }

    private func sizeAdjustedContent(_ content: Content) -> some View {
        if #available(macOS 11.0, *) {
            return AnyView(content.controlSize(.large))
        } else {
            return AnyView(content.controlSize(.regular))
        }
    }
}
