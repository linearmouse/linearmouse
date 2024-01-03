// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct FormViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
                .formStyle(.grouped)
        } else {
            ScrollView {
                content
                    .padding(40)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct SectionViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
        } else {
            content

            Spacer()
                .frame(height: 30)
        }
    }
}

struct PickerViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
        } else {
            // TODO: fixedSize?
            content
        }
    }
}

func withDescription<View1: View, View2: View>(@ViewBuilder content: () -> TupleView<(View1, View2)>) -> some View {
    let c = content()

    if #available(macOS 13.0, *) {
        return Group {
            c.value.0
            c.value.1
        }
    } else {
        return VStack(alignment: .leading) {
            c.value.0
            c.value.1
                .controlSize(.small)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

func labelWithDescription<View1: View,
    View2: View>(@ViewBuilder content: () -> TupleView<(View1, View2)>) -> some View {
    let c = content()

    if #available(macOS 13.0, *) {
        return Group {
            c.value.0
            c.value.1
        }
    } else {
        return VStack(alignment: .trailing) {
            c.value.0
            c.value.1
                .controlSize(.small)
                .foregroundColor(.secondary)
        }
    }
}
