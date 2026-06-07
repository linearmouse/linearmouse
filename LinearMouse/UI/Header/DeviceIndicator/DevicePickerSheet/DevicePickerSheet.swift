// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Defaults
import SwiftUI

struct DevicePickerSheet: View {
    @Binding var isPresented: Bool
    @State private var autoSwitchToActiveDevice = Defaults[.autoSwitchToActiveDevice]
    @State private var selection: DevicePickerSelection?
    @State private var showDeleteAlert = false

    @ObservedObject private var schemeState: SchemeState = .shared
    @ObservedObject private var deviceState: DeviceState = .shared
    @ObservedObject private var deviceManager: DeviceManager = .shared

    private var selectedDeviceMatcher: DeviceMatcher? {
        selection?.deviceMatcher
    }

    private var shouldShowDeleteButton: Bool {
        schemeState.hasMatchingSchemes(
            for: selectedDeviceMatcher,
            forApp: schemeState.currentApp,
            forDisplay: schemeState.currentDisplay
        )
    }

    private var canConfirm: Bool {
        autoSwitchToActiveDevice || selectedDeviceMatcher != nil
    }

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { autoSwitchToActiveDevice },
            set: { newValue in
                autoSwitchToActiveDevice = newValue
                if newValue {
                    syncSelectionWithActiveDevice()
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

                Toggle(String(""), isOn: autoSwitchBinding.animation())
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .modifier(SheetToggleSizeModifier())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            DevicePicker(
                selection: $selection,
                onSelectCategory: handleCategorySelection,
                onSelectDevice: handleDeviceSelection
            )
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
            if autoSwitchToActiveDevice {
                syncSelectionWithActiveDevice()
            } else if let selectedDevice = Defaults[.selectedDevice] {
                selection = selection(for: selectedDevice)
            } else {
                syncSelectionWithCurrentDevice()
            }
        }
        .onReceive(deviceManager.$lastActiveDeviceRef.receive(on: RunLoop.main)) { lastActiveDeviceRef in
            if autoSwitchToActiveDevice {
                selection = lastActiveDeviceRef.map { .device($0) }
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

    private func handleCategorySelection(_ category: DeviceMatcher.Category) {
        selection = .category(category)
        autoSwitchToActiveDevice = false
    }

    private func handleDeviceSelection(_ deviceRef: WeakRef<Device>) {
        selection = .device(deviceRef)

        let isSelectingActiveDevice = deviceRef.value === DeviceManager.shared.lastActiveDeviceRef?.value
        if isSelectingActiveDevice {
            autoSwitchToActiveDevice = true
            syncSelectionWithActiveDevice()
        } else if autoSwitchToActiveDevice {
            autoSwitchToActiveDevice = false
        }
    }

    private func syncSelectionWithActiveDevice() {
        selection = deviceManager.lastActiveDeviceRef.map { .device($0) }
    }

    private func syncSelectionWithCurrentDevice() {
        selection = deviceState.currentDeviceRef.map { .device($0) }
    }

    private func selection(for matcher: DeviceMatcher) -> DevicePickerSelection? {
        if let category = matcher.categoryOnlyValue {
            return .category(category)
        }

        return DevicePickerState.shared
            .devices
            .first { deviceModel in
                guard let device = deviceModel.deviceRef.value else {
                    return false
                }

                return matcher.match(with: device)
            }
            .map { .device($0.deviceRef) }
    }

    private func onOK() {
        Defaults[.autoSwitchToActiveDevice] = autoSwitchToActiveDevice

        if !autoSwitchToActiveDevice {
            Defaults[.selectedDevice] = selectedDeviceMatcher
        }

        isPresented = false
    }

    private func confirmDelete() {
        schemeState.deleteMatchingSchemes(
            for: selectedDeviceMatcher,
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
