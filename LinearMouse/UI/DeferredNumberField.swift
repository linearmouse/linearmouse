// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import SwiftUI

struct DeferredNumberField: NSViewRepresentable {
    @Binding var value: Double
    let formatter: NumberFormatter
    let range: ClosedRange<Double>

    init(value: Binding<Double>, formatter: NumberFormatter, range: ClosedRange<Double>) {
        _value = value
        self.formatter = formatter
        self.range = range
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: formattedValue(value))
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.alignment = .right
        textField.delegate = context.coordinator
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byClipping
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        guard !context.coordinator.isEditing else {
            return
        }

        let formatted = formattedValue(value)
        if textField.stringValue != formatted {
            textField.stringValue = formatted
        }
    }

    private func formattedValue(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? ""
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DeferredNumberField
        var isEditing = false

        init(parent: DeferredNumberField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_: Notification) {
            isEditing = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                isEditing = false
                return
            }

            commit(textField)
            isEditing = false
        }

        func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let textField = control as? NSTextField else {
                return false
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commit(textField)
                textField.window?.makeFirstResponder(nil)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                textField.stringValue = parent.formattedValue(parent.value)
                textField.window?.makeFirstResponder(nil)
                return true
            }

            return false
        }

        private func commit(_ textField: NSTextField) {
            let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty,
                  let number = parent.formatter.number(from: trimmed) else {
                textField.stringValue = parent.formattedValue(parent.value)
                return
            }

            let clamped = min(max(number.doubleValue, parent.range.lowerBound), parent.range.upperBound)
            parent.value = clamped
            textField.stringValue = parent.formattedValue(clamped)
        }
    }
}
