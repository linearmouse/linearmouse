// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import SwiftUI

struct ButtonsSettings: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @ObservedObject private var settingsState: SettingsState = .shared

    var body: some View {
        DetailView {
            Group {
                if let destination = settingsState.buttonsNavigationPath.last {
                    destinationView(destination)
                } else {
                    overview
                }
            }
        }
        .onDisappear {
            settingsState.buttonsNavigationPath.removeAll()
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

                destinationButton(
                    .buttonMappings,
                    description: "Assign actions to buttons and gestures"
                )
            }
            .modifier(SectionViewModifier())
        }
        .modifier(FormViewModifier())
    }

    private func destinationButton(
        _ destination: Destination,
        description: LocalizedStringKey
    ) -> some View {
        Button {
            settingsState.buttonsNavigationPath.append(destination)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.title)

                    Text(description)
                        .settingsDescriptionStyle()
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
        Form {
            switch destination {
            case .autoScroll:
                AutoScrollSection()
            case .buttonMappings:
                ButtonMappingsSection()
                SwipeSettingsSection()
            }
        }
        .modifier(FormViewModifier())
    }

    private var forwardIndicator: NSImage {
        NSImage(named: layoutDirection == .rightToLeft ? NSImage.goBackTemplateName : NSImage.goForwardTemplateName)!
    }
}

private extension ButtonsSettings {
    typealias Destination = SettingsState.ButtonsDestination
}
