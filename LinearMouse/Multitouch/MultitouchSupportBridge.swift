// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

/// A thin Swift wrapper around Apple's private, undocumented
/// `MultitouchSupport.framework`, which is the only way to read live
/// finger/contact-count data from a Magic Mouse's touch surface.
///
/// There is no public API for this. `CGEvent`/`IOHIDEvent` scroll fields
/// (see `ScrollWheelEventView`) carry deltas and phase information but never
/// a touch count. This bridge exists solely to support
/// `RequireTwoFingerScrollTransformer` requiring two fingers before a Magic
/// Mouse is allowed to scroll, mirroring trackpad behavior.
///
/// Because this framework is private and undocumented, every symbol lookup
/// here can fail on a future macOS release. Every entry point is designed to
/// fail safely (return nil / false) rather than crash, so that a broken
/// bridge simply disables two-finger gating instead of breaking scrolling
/// entirely.
final class MultitouchSupportBridge {
    static let shared = MultitouchSupportBridge()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "MultitouchSupportBridge")

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    typealias DeviceRef = UnsafeMutableRawPointer

    // MARK: - Raw touch struct
    //
    // This layout is not documented by Apple. It is reconstructed from
    // widely-circulated community reverse-engineering of this framework
    // (e.g. jnordberg/FingerMgmt and similar open-source projects) and
    // verified empirically against a real Magic Mouse during development.

    struct Touch {
        var frame: Int32
        var timestamp: Double
        var identifier: Int32
        var state: Int32
        var fingerID: Int32
        var handID: Int32
        var normalizedPosition: (x: Float, y: Float)
        var normalizedVelocity: (x: Float, y: Float)
        var size: Float
        var zero1: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var mmPosition: (x: Float, y: Float)
        var mmVelocity: (x: Float, y: Float)
        var zero2a: Int32
        var zero2b: Int32
        var unknown2: Float
    }

    // MARK: - C function signatures
    //
    // The touches parameter is a raw pointer (rather than
    // UnsafeMutablePointer<Touch>?) because the Swift compiler refuses to
    // treat a @convention(c) function type referencing a pointer to a
    // non-@objc Swift struct as C-representable. Callers bind the memory to
    // `Touch` themselves.

    private typealias ContactFrameCallback = @convention(c) (
        DeviceRef?,
        UnsafeMutableRawPointer?,
        Int32,
        Double,
        Int32
    ) -> Int32

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterContactFrameCallbackFn = @convention(c) (DeviceRef?, ContactFrameCallback?) -> Void
    private typealias DeviceStartFn = @convention(c) (DeviceRef?, Int32) -> Void
    private typealias DeviceStopFn = @convention(c) (DeviceRef?) -> Void
    private typealias DeviceIsBuiltInFn = @convention(c) (DeviceRef?) -> Bool

    private let handle: UnsafeMutableRawPointer?
    private let deviceCreateList: CreateListFn?
    private let registerContactFrameCallback: RegisterContactFrameCallbackFn?
    private let deviceStart: DeviceStartFn?
    private let deviceStop: DeviceStopFn?
    private let deviceIsBuiltIn: DeviceIsBuiltInFn?

    /// Whether every symbol this bridge needs was successfully resolved.
    /// Callers must check this before relying on any other method.
    let isAvailable: Bool

    private init() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
            os_log(
                "Failed to dlopen MultitouchSupport.framework: %{public}@",
                log: Self.log,
                type: .error,
                String(cString: dlerror())
            )
            self.handle = nil
            deviceCreateList = nil
            registerContactFrameCallback = nil
            deviceStart = nil
            deviceStop = nil
            deviceIsBuiltIn = nil
            isAvailable = false
            return
        }
        self.handle = handle

        func load<T>(_ name: String, as _: T.Type) -> T? {
            guard let sym = dlsym(handle, name) else {
                os_log(
                    "Failed to resolve symbol %{public}@ in MultitouchSupport.framework",
                    log: Self.log,
                    type: .error,
                    name
                )
                return nil
            }
            return unsafeBitCast(sym, to: T.self)
        }

        deviceCreateList = load("MTDeviceCreateList", as: CreateListFn.self)
        registerContactFrameCallback = load(
            "MTRegisterContactFrameCallback",
            as: RegisterContactFrameCallbackFn.self
        )
        deviceStart = load("MTDeviceStart", as: DeviceStartFn.self)
        deviceStop = load("MTDeviceStop", as: DeviceStopFn.self)
        deviceIsBuiltIn = load("MTDeviceIsBuiltIn", as: DeviceIsBuiltInFn.self)

        isAvailable = deviceCreateList != nil
            && registerContactFrameCallback != nil
            && deviceStart != nil
            && deviceStop != nil
            && deviceIsBuiltIn != nil
    }

    // `MTDeviceCreateList` hands back device pointers that live inside this
    // array's own storage. If the array is released, those pointers can be
    // left dangling (in practice this doesn't crash - the memory stays
    // mapped - but every touch callback frame silently reports zero
    // contacts, since the device object being pointed to is gone). Keeping
    // the array retained for the bridge's lifetime is what keeps the
    // devices we've handed out alive.
    private var retainedDeviceLists: [CFMutableArray] = []

    /// All currently connected multitouch-capable devices (trackpads and
    /// multitouch mice alike).
    func allDevices() -> [DeviceRef] {
        guard isAvailable, let deviceCreateList else {
            return []
        }
        guard let listUnmanaged = deviceCreateList() else {
            return []
        }
        let list = listUnmanaged.takeRetainedValue()
        retainedDeviceLists.append(list)
        let count = CFArrayGetCount(list)
        return (0..<count).compactMap { i in
            CFArrayGetValueAtIndex(list, i).map { UnsafeMutableRawPointer(mutating: $0) }
        }
    }

    /// The first connected multitouch device that isn't a built-in trackpad.
    /// A Magic Mouse is currently the only multitouch device Apple ships that
    /// isn't built into the Mac, so in practice this is "the Magic Mouse" as
    /// long as at most one is paired.
    func firstExternalDevice() -> DeviceRef? {
        guard isAvailable, let deviceIsBuiltIn else {
            return nil
        }
        return allDevices().first { !deviceIsBuiltIn($0) }
    }

    /// Registers `onFrame` to be called every time the given device reports a
    /// new touch frame, with the current number of active contacts, and
    /// starts the device's callback delivery. `onFrame` may be called from an
    /// arbitrary background thread/run loop owned by MultitouchSupport.
    ///
    /// Returns false (without registering or starting) if the bridge isn't
    /// available.
    @discardableResult
    func start(_ device: DeviceRef, onFrame: @escaping (Int) -> Void) -> Bool {
        guard isAvailable, let registerContactFrameCallback, let deviceStart else {
            return false
        }

        ContactFrameDispatchTable.shared.register(device: device, handler: onFrame)

        let callback: ContactFrameCallback = { device, _, numTouches, _, _ in
            guard let device else {
                return 0
            }
            ContactFrameDispatchTable.shared.dispatch(device: device, fingerCount: Int(numTouches))
            return 0
        }

        registerContactFrameCallback(device, callback)
        deviceStart(device, 0)
        return true
    }

    func stop(_ device: DeviceRef) {
        ContactFrameDispatchTable.shared.unregister(device: device)
        deviceStop?(device)
    }
}

/// `MTRegisterContactFrameCallback` takes a plain C function pointer with no
/// context/refcon parameter, so there's no way to close over Swift state
/// directly in the callback. This table maps each device's pointer identity
/// back to the Swift closure that should handle its frames.
private final class ContactFrameDispatchTable {
    static let shared = ContactFrameDispatchTable()

    private let lock = NSLock()
    private var handlers: [UInt: (Int) -> Void] = [:]

    private init() {}

    func register(device: MultitouchSupportBridge.DeviceRef, handler: @escaping (Int) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        handlers[UInt(bitPattern: device)] = handler
    }

    func unregister(device: MultitouchSupportBridge.DeviceRef) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: UInt(bitPattern: device))
    }

    func dispatch(device: MultitouchSupportBridge.DeviceRef, fingerCount: Int) {
        lock.lock()
        let handler = handlers[UInt(bitPattern: device)]
        lock.unlock()
        handler?(fingerCount)
    }
}
