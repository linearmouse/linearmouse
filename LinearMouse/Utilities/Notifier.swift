// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation
import UserNotifications

class Notifier: NSObject {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private var didSetup = false

    func setup() {
        guard !didSetup else {
            return
        }
        didSetup = true
        // Only set the delegate now; request authorization lazily on first notification
        center.delegate = self
    }

    func notify(title: String, body: String) {
        if !didSetup {
            center.delegate = self
            didSetup = true
        }

        center.getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            let send: () -> Void = {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body

                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )

                self.center.add(request, withCompletionHandler: nil)
            }

            if settings.authorizationStatus == .notDetermined {
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    send()
                }
            } else {
                send()
            }
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
            -> Void
    ) {
        // Ensure banners appear when the app is in the foreground
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
