// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Defaults
import SwiftUI

struct DevicePickerSheet: View {
    @Binding var isPresented: Bool
    @State private var autoSwitchToActiveDevice = Defaults[.autoSwitchToActiveDevice]
    @State private var selectedDeviceRef: WeakRef<Device>?
    @State private var showDeleteAlert = false

    @ObservedObject private var schemeState: SchemeState = .shared
    @ObservedObject private var deviceState: DeviceState = .shared

    private var selectedDevice: Device? {
        selectedDeviceRef?.value
    }

    private var shouldShowDeleteButton: Bool {
        schemeState.hasMatchingSchemes(
            for: selectedDevice,
            forApp: schemeState.currentApp,
            forDisplay: schemeState.currentDisplay
        )
    }

    private var canConfirm: Bool {
        autoSwitchToActiveDevice || selectedDeviceRef?.value != nil
    }

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { autoSwitchToActiveDevice },
            set: { newValue in
                autoSwitchToActiveDevice = newValue
                if newValue {
                    syncSelectionWithCurrentDevice()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto switch to the active device")
                    Text("Automatically follow the device that is currently active.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: autoSwitchBinding.animation())
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .modifier(SheetToggleSizeModifier())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            DevicePicker(selectedDeviceRef: $selectedDeviceRef) { deviceRef in
                handleDeviceSelection(deviceRef)
            }
            .frame(minHeight: 248, maxHeight: 320)

            HStack(spacing: 8) {
                if shouldShowDeleteButton {
                    Button("Delete…", action: onDelete)
                        .sheetDestructiveActionStyle()
                }

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .sheetSecondaryActionStyle()
                .asCancelAction()

                Button("OK", action: onOK)
                    .sheetPrimaryActionStyle()
                    .asDefaultAction()
                    .disabled(!canConfirm)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(minWidth: 372)
        .onExitCommand {
            isPresented = false
        }
        .onAppear {
            autoSwitchToActiveDevice = Defaults[.autoSwitchToActiveDevice]
            syncSelectionWithCurrentDevice()
        }
        .onReceive(deviceState.$currentDeviceRef.receive(on: RunLoop.main)) { currentDeviceRef in
            if autoSwitchToActiveDevice {
                selectedDeviceRef = currentDeviceRef
            }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete Configuration?"),
                message: Text("This will delete all settings for the selected device."),
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

    private func handleDeviceSelection(_ deviceRef: WeakRef<Device>) {
        selectedDeviceRef = deviceRef

        let isSelectingActiveDevice = deviceRef.value === DeviceManager.shared.lastActiveDeviceRef?.value
        if isSelectingActiveDevice {
            autoSwitchToActiveDevice = true
            syncSelectionWithCurrentDevice()
        } else if autoSwitchToActiveDevice {
            autoSwitchToActiveDevice = false
        }
    }

    private func syncSelectionWithCurrentDevice() {
        selectedDeviceRef = deviceState.currentDeviceRef
    }

    private func onOK() {
        Defaults[.autoSwitchToActiveDevice] = autoSwitchToActiveDevice

        if !autoSwitchToActiveDevice {
            deviceState.currentDeviceRef = selectedDeviceRef
        }

        isPresented = false
    }

    private func confirmDelete() {
        schemeState.deleteMatchingSchemes(
            for: selectedDevice,
            forApp: schemeState.currentApp,
            forDisplay: schemeState.currentDisplay
        )
        isPresented = false
    }
}

private struct SheetToggleSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.controlSize(.small)
    }
}
