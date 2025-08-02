// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine
import SwiftUI

// MARK: - Device Indicator Button

class DeviceIndicatorButton: NSButton {
    private var cancellables = Set<AnyCancellable>()
    private let deviceState = DeviceIndicatorState.shared
    private var currentSheet: NSViewController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
        setupObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
        setupObservers()
    }

    private func setupButton() {
        // Styling is handled in ToolbarManager
        controlSize = .regular

        // Set initial title
        title = deviceState.activeDeviceName ?? "Unknown"

        // Configure appearance
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        contentTintColor = .labelColor

        // Ensure text is visible with proper color
        updateTextColor()

        // Add action
        target = self
        action = #selector(buttonClicked)
    }

    private func updateTextColor() {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlTextColor,
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func setupObservers() {
        // Observe device name changes
        deviceState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.title = self?.deviceState.activeDeviceName ?? "Unknown"
                self?.updateTextColor()
            }
            .store(in: &cancellables)
    }

    @objc private func buttonClicked() {
        // Dismiss current sheet if any
        if let currentSheet {
            currentSheet.dismiss(nil)
            self.currentSheet = nil
            return
        }

        // Create a binding that can close the sheet
        let isPresented = CurrentValueSubject<Bool, Never>(true)
        let binding = Binding<Bool>(
            get: { isPresented.value },
            set: { newValue in
                isPresented.send(newValue)
                if !newValue {
                    DispatchQueue.main.async { [weak self] in
                        self?.currentSheet?.dismiss(nil)
                        self?.currentSheet = nil
                    }
                }
            }
        )

        let contentView = DevicePickerSheet(isPresented: binding)
        let hostingController = createSheetController(rootView: contentView, size: NSSize(width: 400, height: 300))

        if let window {
            currentSheet = hostingController
            window.contentViewController?.presentAsSheet(hostingController)
        }
    }
}

// MARK: - App Indicator Button

class AppIndicatorButton: NSButton {
    private var cancellables = Set<AnyCancellable>()
    private let schemeState = SchemeState.shared
    private var currentSheet: NSViewController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
        setupObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
        setupObservers()
    }

    private func setupButton() {
        // Styling is handled in ToolbarManager
        controlSize = .regular

        // Set initial title
        title = schemeState.currentAppName ?? NSLocalizedString("All Apps", comment: "")

        // Configure appearance
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        contentTintColor = .labelColor

        // Ensure text is visible with proper color
        updateTextColor()

        // Add action
        target = self
        action = #selector(buttonClicked)
    }

    private func updateTextColor() {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlTextColor,
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func setupObservers() {
        // Observe app name changes
        schemeState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.title = self?.schemeState.currentAppName ?? NSLocalizedString("All Apps", comment: "")
                self?.updateTextColor()
            }
            .store(in: &cancellables)
    }

    @objc private func buttonClicked() {
        // Dismiss current sheet if any
        if let currentSheet {
            currentSheet.dismiss(nil)
            self.currentSheet = nil
            return
        }

        // Create a binding that can close the sheet
        let isPresented = CurrentValueSubject<Bool, Never>(true)
        let binding = Binding<Bool>(
            get: { isPresented.value },
            set: { newValue in
                isPresented.send(newValue)
                if !newValue {
                    DispatchQueue.main.async { [weak self] in
                        self?.currentSheet?.dismiss(nil)
                        self?.currentSheet = nil
                    }
                }
            }
        )

        let contentView = AppPickerSheet(isPresented: binding)
        let hostingController = createSheetController(rootView: contentView, size: NSSize(width: 500, height: 300))

        if let window {
            currentSheet = hostingController
            window.contentViewController?.presentAsSheet(hostingController)
        }
    }
}

// MARK: - Display Indicator Button

class DisplayIndicatorButton: NSButton {
    private var cancellables = Set<AnyCancellable>()
    private let schemeState = SchemeState.shared
    private var currentSheet: NSViewController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
        setupObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
        setupObservers()
    }

    private func setupButton() {
        // Styling is handled in ToolbarManager
        controlSize = .regular

        // Set initial title
        title = schemeState.currentDisplay ?? NSLocalizedString("All Displays", comment: "")

        // Configure appearance
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        contentTintColor = .labelColor

        // Ensure text is visible with proper color
        updateTextColor()

        // Add action
        target = self
        action = #selector(buttonClicked)
    }

    private func updateTextColor() {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlTextColor,
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func setupObservers() {
        // Observe display name changes
        schemeState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.title = self?.schemeState.currentDisplay ?? NSLocalizedString("All Displays", comment: "")
                self?.updateTextColor()
            }
            .store(in: &cancellables)
    }

    @objc private func buttonClicked() {
        // Dismiss current sheet if any
        if let currentSheet {
            currentSheet.dismiss(nil)
            self.currentSheet = nil
            return
        }

        // Create a binding that can close the sheet
        let isPresented = CurrentValueSubject<Bool, Never>(true)
        let binding = Binding<Bool>(
            get: { isPresented.value },
            set: { newValue in
                isPresented.send(newValue)
                if !newValue {
                    DispatchQueue.main.async { [weak self] in
                        self?.currentSheet?.dismiss(nil)
                        self?.currentSheet = nil
                    }
                }
            }
        )

        let contentView = DisplayPickerSheet(isPresented: binding)
        let hostingController = createSheetController(rootView: contentView, size: NSSize(width: 400, height: 250))

        if let window {
            currentSheet = hostingController
            window.contentViewController?.presentAsSheet(hostingController)
        }
    }
}

// MARK: - Helper Functions

private func createSheetController<Content: View>(rootView: Content, size: NSSize) -> NSViewController {
    let hostingController = NSHostingController(rootView: rootView)

    // Disable autoresizing to prevent constraint conflicts
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false

    // Create a wrapper view controller to handle sizing properly
    let wrapperController = NSViewController()
    wrapperController.view = NSView()
    wrapperController.view.frame = NSRect(origin: .zero, size: size)

    // Add hosting controller as child
    wrapperController.addChild(hostingController)
    wrapperController.view.addSubview(hostingController.view)

    // Set up constraints to fill the wrapper view
    NSLayoutConstraint.activate([
        hostingController.view.topAnchor.constraint(equalTo: wrapperController.view.topAnchor),
        hostingController.view.leadingAnchor.constraint(equalTo: wrapperController.view.leadingAnchor),
        hostingController.view.trailingAnchor.constraint(equalTo: wrapperController.view.trailingAnchor),
        hostingController.view.bottomAnchor.constraint(equalTo: wrapperController.view.bottomAnchor)
    ])

    // Set preferred content size on the wrapper
    wrapperController.preferredContentSize = size

    return wrapperController
}
