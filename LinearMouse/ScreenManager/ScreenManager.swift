// MIT License
// Copyright (c) 2021-2023 LinearMouse

import AppKit
import Combine
import CoreGraphics
import os.log

class ScreenManager: ObservableObject {
    static let shared = ScreenManager()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ScreenManager")

    @Published private(set) var screens: [NSScreen] = []

    @Published private(set) var currentScreen: NSScreen?

    private var timer: Timer?

    private var subscriptions: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self = self else {
                    return
                }

                self.updateScreens()
                self.update()
            }
            .store(in: &subscriptions)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            self.updateScreens()
            self.update()
        }
    }

    private func updateScreens() {
        screens = NSScreen.screens
        os_log("Displays changed: %{public}@", String(describing: screens))
    }

    private func update() {
        let screen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        if currentScreen != screen {
            currentScreen = screen
            os_log(
                "Current display changed: %{public}@: %{public}@",
                String(describing: screen),
                String(describing: screen?.name)
            )
        }

        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self else {
                return
            }

            self.update()
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var ioServicePort: io_service_t? {
        guard let displayID = displayID else {
            return nil
        }

        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"), &iter) ==
            KERN_SUCCESS else {
            return nil
        }

        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while true {
            guard service != MACH_PORT_NULL else {
                break
            }

            let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))
                .takeRetainedValue() as NSDictionary

            let vendorID = info.value(forKey: kDisplayVendorID) as? UInt32
            let productID = info.value(forKey: kDisplayProductID) as? UInt32
            let serialNumber = info.value(forKey: kDisplaySerialNumber) as? UInt32

            if CGDisplayVendorNumber(displayID) == vendorID,
               CGDisplayModelNumber(displayID) == productID,
               CGDisplaySerialNumber(displayID) == serialNumber ?? 0 {
                return service
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }

        return nil
    }

    var name: String? {
        guard let service = ioServicePort else {
            return nil
        }

        defer { IOObjectRelease(service) }

        let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))
            .takeRetainedValue() as NSDictionary

        let productNames = info.value(forKey: kDisplayProductName) as? NSDictionary

        return productNames?.allValues.first as? String
    }

    var nameOrLocalizedName: String? {
        name ?? localizedName
    }
}
