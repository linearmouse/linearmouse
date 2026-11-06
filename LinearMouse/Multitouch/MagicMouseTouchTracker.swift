// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import os.log

/// Tracks the live finger count on a connected Magic Mouse, backed by
/// `MultitouchSupportBridge`.
///
/// Attaches when `DeviceManager` reports a Magic Mouse is connected, and
/// detaches when it disappears, so it works across sleep/wake and
/// unpair/re-pair without leaking a stale device reference.
///
/// `isAvailable` is false whenever there's no live finger-count signal to
/// trust, whether because the private framework failed to load, no Magic
/// Mouse is connected, or the multitouch device hasn't been found yet.
/// Callers (`RequireTwoFingerScrollTransformer`) must treat that as "fail
/// open" - i.e. don't block scrolling - rather than assuming zero fingers.
final class MagicMouseTouchTracker {
    static let shared = MagicMouseTouchTracker()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "MagicMouseTouchTracker")

    private static let attachRetryDelay: TimeInterval = 1
    private static let maxAttachAttempts = 5

    private let bridge: MultitouchSupportBridge
    private let lock = NSLock()
    private var _fingerCount = 0
    // Guarded by `lock`, not just main-thread confinement: `RequireTwoFingerScrollTransformer`
    // reads this from LinearMouse's dedicated event-processing thread (see `EventThread`),
    // while every write here happens on the main thread. Without a shared lock, the event
    // thread has no guarantee it will ever observe a write made on another thread - it could
    // see a stale `false` indefinitely and silently disable two-finger gating for good.
    private var _isAvailable = false
    private var attachedDevice: MultitouchSupportBridge.DeviceRef?
    private var attachAttempts = 0
    private var retryWorkItem: DispatchWorkItem?
    private var cancellable: AnyCancellable?

    var fingerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fingerCount
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAvailable
    }

    init(bridge: MultitouchSupportBridge = .shared) {
        self.bridge = bridge

        guard bridge.isAvailable else {
            os_log(
                "MultitouchSupport bridge unavailable; two-finger scroll gating is disabled",
                log: Self.log,
                type: .error
            )
            return
        }

        cancellable = DeviceManager.shared.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.reconcile(withMagicMouseConnected: devices.contains(where: \.isAppleMagicMouse))
            }
    }

    private func reconcile(withMagicMouseConnected magicMouseConnected: Bool) {
        if magicMouseConnected {
            guard attachedDevice == nil else {
                return
            }
            attachAttempts = 0
            attemptAttach()
        } else {
            retryWorkItem?.cancel()
            retryWorkItem = nil
            detach()
        }
    }

    private func attemptAttach() {
        attachAttempts += 1

        guard let device = bridge.firstExternalDevice() else {
            guard attachAttempts < Self.maxAttachAttempts else {
                os_log(
                    "Gave up looking for the Magic Mouse's multitouch device after %d attempts",
                    log: Self.log,
                    type: .error,
                    Self.maxAttachAttempts
                )
                return
            }

            let workItem = DispatchWorkItem { [weak self] in self?.attemptAttach() }
            retryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.attachRetryDelay, execute: workItem)
            return
        }

        bridge.start(device) { [weak self] count in
            guard let self else {
                return
            }
            lock.lock()
            _fingerCount = count
            lock.unlock()
        }

        attachedDevice = device
        lock.lock()
        _isAvailable = true
        lock.unlock()
        os_log("Attached to Magic Mouse multitouch device", log: Self.log, type: .info)
    }

    private func detach() {
        if let attachedDevice {
            bridge.stop(attachedDevice)
        }
        attachedDevice = nil
        lock.lock()
        _isAvailable = false
        _fingerCount = 0
        lock.unlock()
    }
}
