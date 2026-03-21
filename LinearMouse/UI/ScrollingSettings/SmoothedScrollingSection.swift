// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import SwiftUI

extension ScrollingSettings {
    struct SmoothedScrollingSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared
        @State private var isPresetPickerPresented = false

        private var visiblePresets: [Scheme.Scrolling.Smoothed.Preset] {
            let recommended = Scheme.Scrolling.Smoothed.Preset.recommendedCases
            let current = state.smoothedPreset
            return recommended.contains(current) ? recommended : [current] + recommended
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                withDescription {
                    Text("Scrolling curve")
                    Text("Choose a feel preset.")
                }

                presetPicker

                sliderRow(
                    title: "Scroll response",
                    description: "(0–1)",
                    value: Binding(
                        get: { state.smoothedResponse },
                        set: { state.smoothedResponse = $0 }
                    ),
                    range: 0.0 ... 1.0,
                    minimumValueLabel: "Loose",
                    maximumValueLabel: "Immediate",
                    formatter: state.smoothedResponseFormatter
                )

                sliderRow(
                    title: "Scroll speed",
                    description: "(0–3)",
                    value: Binding(
                        get: { state.smoothedSpeed },
                        set: { state.smoothedSpeed = $0 }
                    ),
                    range: 0.0 ... 3.0,
                    minimumValueLabel: "Slow",
                    maximumValueLabel: "Fast",
                    formatter: state.smoothedSpeedFormatter
                )

                sliderRow(
                    title: "Scroll acceleration",
                    description: "(0–3)",
                    value: Binding(
                        get: { state.smoothedAcceleration },
                        set: { state.smoothedAcceleration = $0 }
                    ),
                    range: 0.0 ... 3.0,
                    minimumValueLabel: "Flat",
                    maximumValueLabel: "Adaptive",
                    formatter: state.smoothedAccelerationFormatter
                )

                sliderRow(
                    title: "Scroll inertia",
                    description: "(0–3)",
                    value: Binding(
                        get: { state.smoothedInertia },
                        set: { state.smoothedInertia = $0 }
                    ),
                    range: 0.0 ... 3.0,
                    minimumValueLabel: "Short",
                    maximumValueLabel: "Long",
                    formatter: state.smoothedInertiaFormatter
                )

                HStack(spacing: 10) {
                    Button("Restore default preset") {
                        state.scrollingMode = .smoothed
                        state.restoreDefaultSmoothedPreset()
                    }

                    if state.direction == .horizontal {
                        Button("Copy settings from vertical") {
                            state.scheme.scrolling.smoothed.horizontal = state.mergedScheme.scrolling.smoothed.vertical
                        }
                    }
                }
            }
        }

        private var presetPicker: some View {
            Button {
                isPresetPickerPresented.toggle()
            } label: {
                HStack(spacing: 12) {
                    SmoothedCurvePreview(
                        configuration: state.smoothedPreviewConfiguration(for: state.smoothedPreset),
                        highlighted: false,
                        style: .compact
                    )
                    .frame(width: 92, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.smoothedPreset.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(presetFootnote(for: state.smoothedPreset))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("▾")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresetPickerPresented, arrowEdge: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visiblePresets) { preset in
                            presetMenuRow(for: preset)
                        }
                    }
                    .padding(10)
                }
                .frame(width: 300, height: 400)
            }
        }

        private func presetMenuRow(for preset: Scheme.Scrolling.Smoothed.Preset) -> some View {
            let isSelected = state.smoothedPreset == preset
            let configuration = state.smoothedPreviewConfiguration(for: preset)

            return Button {
                state.scrollingMode = .smoothed
                state.smoothedPreset = preset
                isPresetPickerPresented = false
            } label: {
                HStack(spacing: 12) {
                    SmoothedCurvePreview(
                        configuration: configuration,
                        highlighted: isSelected,
                        style: .compact
                    )
                    .frame(width: 92, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(preset.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if preset == .custom {
                                Text("Editable")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Text("Selected")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)
        }

        private func presetFootnote(for preset: Scheme.Scrolling.Smoothed.Preset) -> String {
            switch preset {
            case .custom:
                return "Use this when you want to fine-tune the feel yourself."
            case .linear:
                return "Direct and immediate, with a short controlled tail."
            case .easeIn:
                return "Soft start that builds momentum as you keep scrolling."
            case .easeOut:
                return "Fast initial response that settles quickly."
            case .easeInOut:
                return "Balanced ramp-up and release."
            case .easeOutIn:
                return "Quick pickup with a softer body."
            case .quadratic:
                return "Ease-in quad with a noticeable but manageable ramp-up."
            case .cubic:
                return "Ease-in cubic with a stronger progressive build."
            case .quartic:
                return "Ease-in quartic with the strongest front-loaded ramp."
            case .easeOutCubic:
                return "Fast cubic pickup that settles into a shorter tail."
            case .easeInOutCubic:
                return "Cubic ease-in-out with a weightier middle section."
            case .easeOutQuartic:
                return "Very fast quartic pickup with a crisp release."
            case .easeInOutQuartic:
                return "Quartic ease-in-out with the boldest mid-curve."
            case .quintic:
                return "Aggressive curve with a deep push."
            case .sine:
                return "Gentle, wave-like motion."
            case .exponential:
                return "Very strong build-up for bold flicks."
            case .circular:
                return "Rounded entry with a stable tail."
            case .back:
                return "Taut and punchy with a tighter stop."
            case .bounce:
                return "Playful, short-lived motion."
            case .elastic:
                return "Springy movement with a longer tail."
            case .spring:
                return "Fast pickup with a lively, cushioned rebound."
            case .natural:
                return "Legacy balanced preset kept for compatibility."
            case .smooth:
                return "Stable and fluid, with a longer carry than Linear."
            case .snappy:
                return "The quickest start, with the shortest tail."
            case .gentle:
                return "Soft and gliding, with the longest tail."
            }
        }

        private func sliderRow(
            title: LocalizedStringKey,
            description: LocalizedStringKey,
            value: Binding<Double>,
            range: ClosedRange<Double>,
            minimumValueLabel: LocalizedStringKey,
            maximumValueLabel: LocalizedStringKey,
            formatter: NumberFormatter
        ) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Slider(
                    value: value,
                    in: range
                ) {
                    labelWithDescription {
                        Text(title)
                        Text(description)
                    }
                } minimumValueLabel: {
                    Text(minimumValueLabel)
                } maximumValueLabel: {
                    Text(maximumValueLabel)
                }

                DeferredNumberField(
                    value: value,
                    formatter: formatter,
                    range: range
                )
                .frame(width: 60, height: 22)
            }
        }
    }
}

private struct SmoothedCurvePreview: View {
    enum Style {
        case compact
        case large
    }

    let configuration: Scheme.Scrolling.Smoothed
    let highlighted: Bool
    let style: Style

    private var samples: [CGFloat] {
        let count = style == .large ? 36 : 24
        return (0 ..< count).map { index in
            let t = CGFloat(index) / CGFloat(max(count - 1, 1))
            return previewValue(at: t)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let rect = geometry.frame(in: .local)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(highlighted ? Color.accentColor.opacity(0.08) : Color(NSColor.windowBackgroundColor))

                grid(in: rect)
                    .stroke(Color.secondary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                fillPath(in: rect)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(highlighted ? 0.34 : 0.22),
                                Color.accentColor.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                curvePath(in: rect)
                    .stroke(
                        highlighted ? Color.accentColor : Color.primary.opacity(0.72),
                        style: StrokeStyle(lineWidth: highlighted ? 2.2 : 1.8, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    private func grid(in rect: CGRect) -> Path {
        var path = Path()

        for step in 1 ..< 4 {
            let y = rect.minY + (rect.height / 4) * CGFloat(step)
            path.move(to: CGPoint(x: rect.minX + 8, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - 8, y: y))
        }

        return path
    }

    private func fillPath(in rect: CGRect) -> Path {
        var path = curvePath(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 8))
        path.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8))
        path.closeSubpath()
        return path
    }

    private func curvePath(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: 8, dy: 8)
        let count = max(samples.count - 1, 1)

        return Path { path in
            for (index, sample) in samples.enumerated() {
                let x = insetRect.minX + insetRect.width * CGFloat(index) / CGFloat(count)
                let y = insetRect.maxY - insetRect.height * sample
                let point = CGPoint(x: x, y: y)

                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func previewValue(at t: CGFloat) -> CGFloat {
        let preset = configuration.resolvedPreset

        switch preset {
        case .custom:
            return dynamicPreviewValue(at: t)
        case .linear:
            return t
        case .easeIn:
            return pow(t, 2.2)
        case .easeOut:
            return 1 - pow(1 - t, 2.2)
        case .easeInOut:
            return easeInOutPower(t, power: 2.0)
        case .easeOutIn:
            return easeOutInPower(t, power: 2.0)
        case .quadratic:
            return pow(t, 2.0)
        case .cubic:
            return pow(t, 3.0)
        case .quartic:
            return pow(t, 4.0)
        case .easeOutCubic:
            return 1 - pow(1 - t, 3.0)
        case .easeInOutCubic:
            return easeInOutPower(t, power: 3.0)
        case .easeOutQuartic:
            return 1 - pow(1 - t, 4.0)
        case .easeInOutQuartic:
            return easeInOutPower(t, power: 4.0)
        case .quintic:
            return pow(t, 5.0)
        case .sine:
            return 1 - cos((t * .pi) / 2)
        case .exponential:
            return t == 0 ? 0 : pow(2, 10 * (t - 1))
        case .circular:
            return 1 - sqrt(max(0, 1 - t * t))
        case .back:
            return backCurve(t)
        case .bounce:
            return bounceCurve(t)
        case .elastic:
            return elasticCurve(t)
        case .spring:
            return springCurve(t)
        case .natural:
            return easeOutInPower(t, power: 1.55)
        case .smooth:
            return easeInOutPower(t, power: 1.45)
        case .snappy:
            return 1 - pow(1 - t, 3.6)
        case .gentle:
            return 1 - pow(1 - t, 1.35)
        }
    }

    private func dynamicPreviewValue(at t: CGFloat) -> CGFloat {
        let response = CGFloat(configuration.response?.asTruncatedDouble ?? 0.68)
        let speed = CGFloat(configuration.speed?.asTruncatedDouble ?? 1.0)
        let acceleration = CGFloat(configuration.acceleration?.asTruncatedDouble ?? 1.0)
        let inertia = CGFloat(configuration.inertia?.asTruncatedDouble ?? 0.8)

        let leadingPower = max(0.8, 2.2 - response * 1.4 - speed * 0.15)
        let tailPower = max(1.1, 1.2 + inertia * 0.7 + acceleration * 0.08)
        let midpoint = min(max(0.35 + response * 0.18, 0.25), 0.75)

        if t < midpoint {
            let local = t / midpoint
            return pow(local, leadingPower) * 0.52
        }

        let local = (t - midpoint) / max(1 - midpoint, 0.001)
        return 0.52 + (1 - pow(1 - local, tailPower)) * 0.48
    }

    private func easeInOutPower(_ t: CGFloat, power: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 0.5 * pow(t * 2, power)
        }

        return 1 - 0.5 * pow((1 - t) * 2, power)
    }

    private func easeOutInPower(_ t: CGFloat, power: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 0.5 * (1 - pow(1 - t * 2, power))
        }

        return 0.5 + 0.5 * pow((t - 0.5) * 2, power)
    }

    private func backCurve(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.35
        let c3 = c1 + 1
        let value = c3 * t * t * t - c1 * t * t
        return max(0, min(1, value))
    }

    private func bounceCurve(_ t: CGFloat) -> CGFloat {
        let n1: CGFloat = 7.5625
        let d1: CGFloat = 2.75
        let value: CGFloat

        if t < 1 / d1 {
            value = n1 * t * t
        } else if t < 2 / d1 {
            let local = t - 1.5 / d1
            value = n1 * local * local + 0.75
        } else if t < 2.5 / d1 {
            let local = t - 2.25 / d1
            value = n1 * local * local + 0.9375
        } else {
            let local = t - 2.625 / d1
            value = n1 * local * local + 0.984375
        }

        return max(0, min(1, value))
    }

    private func elasticCurve(_ t: CGFloat) -> CGFloat {
        guard t != 0, t != 1 else {
            return t
        }

        let c4 = (2 * CGFloat.pi) / 3
        let value = -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c4)
        return max(0, min(1, value + 1))
    }

    private func springCurve(_ t: CGFloat) -> CGFloat {
        let value = 1 - exp(-6 * t) * cos(8.5 * t)
        return max(0, min(1, value))
    }
}

private struct DeferredNumberField: NSViewRepresentable {
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

private extension Scheme.Scrolling.Smoothed.Preset {
    var displayName: String {
        switch self {
        case .custom:
            return "Custom"
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease In Out"
        case .easeOutIn:
            return "Ease Out In"
        case .quadratic:
            return "Ease In Quad"
        case .cubic:
            return "Ease In Cubic"
        case .quartic:
            return "Ease In Quartic"
        case .easeOutCubic:
            return "Ease Out Cubic"
        case .easeInOutCubic:
            return "Ease In Out Cubic"
        case .easeOutQuartic:
            return "Ease Out Quartic"
        case .easeInOutQuartic:
            return "Ease In Out Quartic"
        case .quintic:
            return "Quintic"
        case .sine:
            return "Sine"
        case .exponential:
            return "Exponential"
        case .circular:
            return "Circular"
        case .back:
            return "Back"
        case .bounce:
            return "Bounce"
        case .elastic:
            return "Elastic"
        case .spring:
            return "Spring"
        case .natural:
            return "Natural"
        case .smooth:
            return "Smooth"
        case .snappy:
            return "Snappy"
        case .gentle:
            return "Gentle"
        }
    }
}
