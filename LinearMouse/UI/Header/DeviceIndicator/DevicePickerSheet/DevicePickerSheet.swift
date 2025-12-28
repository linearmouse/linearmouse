// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Defaults
import SwiftUI

struct DevicePickerSheet: View {
    @Binding var isPresented: Bool
    @Default(.autoSwitchToActiveDevice) var autoSwitchToActiveDevice
    @State private var showDeleteAlert = false

    @ObservedObject private var schemeState: SchemeState = .shared

    private var shouldShowDeleteButton: Bool {
        // Only show if there are matching schemes
        schemeState.hasMatchingSchemes
    }

    var body: some View {
        VStack(spacing: 10) {
            if !autoSwitchToActiveDevice {
                DevicePicker(isPresented: $isPresented)
                    .frame(minHeight: 300)
            }

            Toggle("Auto switch to the active device", isOn: $autoSwitchToActiveDevice.animation())
                .padding()

            HStack {
                if shouldShowDeleteButton {
                    Button("Delete…", action: onDelete)
                        .foregroundColor(.red)
                        .padding([.bottom, .leading])
                }

                Spacer()

                Button("OK") {
                    isPresented = false
                }
                .padding([.bottom, .horizontal])
                .controlSize(.regular)
                .asDefaultAction()
            }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete Configuration?"),
                message: Text("This will delete all settings for the current device."),
                primaryButton: .destructive(Text("Delete")) {
                    confirmDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func onDelete() {
        showDeleteAlert = true
    }

    private func confirmDelete() {
        schemeState.deleteMatchingSchemes()
        isPresented = false
    }
}
