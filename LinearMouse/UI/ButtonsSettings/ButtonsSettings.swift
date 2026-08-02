// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import SwiftUI

struct ButtonsSettings: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @ObservedObject private var deviceState: DeviceState = .shared
    @State private var navigationPath: [Destination] = []

    var body: some View {
        DetailView {
            Group {
                if let destination = navigationPath.last {
                    destinationView(destination)
                } else {
                    overview
                }
            }
        }
        .onReceive(deviceState.$currentDeviceRef) { deviceRef in
            if navigationPath.last == .gestureButton,
               deviceRef?.value?.category != .mouse {
                navigationPath.removeAll()
            }
        }
    }

    private var overview: some View {
        Form {
            UniversalBackForwardSection()

            SwitchPrimaryAndSecondaryButtonsSection()

            ClickDebouncingSection()

            Section {
                destinationButton(
                    .autoScroll,
                    description: "Scroll by moving away from an anchor point, similar to Windows middle-click autoscroll."
                )

                if isMouseDevice {
                    destinationButton(
                        .gestureButton,
                        description: "Press and hold a button while dragging to trigger gestures like switching desktop spaces or opening Mission Control."
                    )
                }

                destinationButton(
                    .buttonMappings,
                    description: "Assign actions to buttons and gestures"
                )
            }
            .modifier(SectionViewModifier())
        }
        .modifier(FormViewModifier())
    }

    private var isMouseDevice: Bool {
        deviceState.currentDeviceRef?.value?.category == .mouse
    }

    private func destinationButton(
        _ destination: Destination,
        description: LocalizedStringKey
    ) -> some View {
        Button {
            navigationPath.append(destination)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.title)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(nsImage: forwardIndicator)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 7, height: 10)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibility(label: Text(destination.title))
        .accessibility(hint: Text(description))
    }

    private func destinationView(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    navigationPath.removeLast()
                } label: {
                    HStack(spacing: 5) {
                        Image(nsImage: backIndicator)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 7, height: 10)
                        Text("Buttons")
                    }
                }
                .buttonStyle(.borderless)

                Divider()
                    .frame(height: 18)

                Text(destination.title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            Form {
                switch destination {
                case .autoScroll:
                    AutoScrollSection()
                case .gestureButton:
                    GestureButtonSection()
                case .buttonMappings:
                    ButtonMappingsSection()
                }
            }
            .modifier(FormViewModifier())
        }
    }

    private var forwardIndicator: NSImage {
        NSImage(named: layoutDirection == .rightToLeft ? NSImage.goBackTemplateName : NSImage.goForwardTemplateName)!
    }

    private var backIndicator: NSImage {
        NSImage(named: layoutDirection == .rightToLeft ? NSImage.goForwardTemplateName : NSImage.goBackTemplateName)!
    }
}

private extension ButtonsSettings {
    enum Destination: Equatable {
        case autoScroll
        case gestureButton
        case buttonMappings

        var title: LocalizedStringKey {
            switch self {
            case .autoScroll:
                return "Autoscroll"
            case .gestureButton:
                return "Gesture Button"
            case .buttonMappings:
                return "Button Mappings"
            }
        }
    }
}
