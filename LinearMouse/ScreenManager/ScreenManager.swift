// MIT License
// Copyright (c) 2021-2023 LinearMouse

import AppKit
import Combine

class ScreenManager: ObservableObject {
    static let shared = ScreenManager()

    @Published private(set) var screens: [NSScreen] = []

    @Published private(set) var currentScreen: NSScreen?

    private var timer: Timer?

    private var subscriptions: Set<AnyCancellable> = []

    init() {
        update()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self = self else {
                    return
                }

                self.update()
            }
            .store(in: &subscriptions)
    }

    private func update() {
        screens = NSScreen.screens

        currentScreen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }

        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else {
                return
            }

            self.update()
        }
    }
}
