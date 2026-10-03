// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Carbon
import Darwin

// Portions adapted from yabai, Copyright (c) 2019 Åsmund Vikane.
// Full MIT permission notice: ThirdPartyNotices/yabai.txt.

/// Runtime-loaded private APIs. Missing symbols fail closed, without activation/raise fallback.
/// Protocol source (MIT):
/// https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/window_manager.c
final class WindowFocus {
    static let shared = WindowFocus()

    struct Target: Equatable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    private typealias FrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>?, UInt32, UInt32)
        -> CGError
    private typealias PostRecord = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>?,
        UnsafeMutablePointer<UInt8>?
    ) -> CGError
    private typealias WindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>?) -> AXError
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>?) -> OSStatus
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias FindWindow = @convention(c) (
        Int32, Int32, Int32, Int32, UnsafeMutablePointer<CGPoint>?, UnsafeMutablePointer<CGPoint>?,
        UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<Int32>?
    ) -> OSStatus
    private typealias ConnectionPID = @convention(c) (Int32, UnsafeMutablePointer<pid_t>?) -> CGError

    // Retain the dlopen handles for the lifetime of the function pointers.
    private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private let processSymbols = dlopen(nil, RTLD_LAZY)
    private let setFrontProcess: FrontProcess?
    private let postRecord: PostRecord?
    private let getWindowID: WindowID?
    private let processForPID: ProcessForPID?
    private let mainConnection: MainConnection?
    private let findWindow: FindWindow?
    private let connectionPID: ConnectionPID?

    private init() {
        setFrontProcess = Self.symbol("_SLPSSetFrontProcessWithOptions", in: skyLight)
        postRecord = Self.symbol("SLPSPostEventRecordTo", in: skyLight)
        getWindowID = Self.symbol("_AXUIElementGetWindow", in: processSymbols)
        processForPID = Self.symbol("GetProcessForPID", in: processSymbols)
        mainConnection = Self.symbol("SLSMainConnectionID", in: skyLight)
        findWindow = Self.symbol("SLSFindWindowAndOwner", in: skyLight)
        connectionPID = Self.symbol("SLSConnectionGetPID", in: skyLight)
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let address = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(address, to: T.self)
    }

    func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindowID, getWindowID(window, &id) == .success, id != 0 else {
            return nil
        }
        return id
    }

    func window(at point: CGPoint) -> Target? {
        guard let mainConnection, let findWindow, let connectionPID else {
            return nil
        }
        var point = point
        var local = CGPoint.zero
        var id: UInt32 = 0
        var owner: Int32 = 0
        var pid: pid_t = 0
        guard findWindow(mainConnection(), 0, 1, 0, &point, &local, &id, &owner) == noErr,
              id != 0, owner != 0, connectionPID(owner, &pid) == .success, pid > 0 else {
            return nil
        }
        // Do not skip an interactive hit to focus another window underneath it.
        return Target(pid: pid, windowID: id)
    }

    func focus(_ target: Target, from previous: Target, isCurrent: () -> Bool) -> Bool {
        guard let setFrontProcess, let postRecord, let processForPID, target.windowID != 0 else {
            return false
        }
        var process = ProcessSerialNumber()
        guard processForPID(target.pid, &process) == noErr else {
            return false
        }
        let sameProcess = target.pid == previous.pid && previous.windowID != 0 && previous.windowID != target.windowID
        return Self.performFocus(
            switchingWithinApplication: sameProcess,
            isCurrent: isCurrent,
            deactivate: {
                var record = Self.stateRecord(windowID: previous.windowID, state: 2)
                return postRecord(&process, &record) == .success
            },
            wait: { Thread.sleep(forTimeInterval: 0.04) },
            activate: {
                if sameProcess {
                    var record = Self.stateRecord(windowID: target.windowID, state: 1)
                    guard postRecord(&process, &record) == .success else {
                        return false
                    }
                }
                guard setFrontProcess(&process, target.windowID, 0x200) == .success else {
                    return false
                }
                var record = Self.keyRecord(windowID: target.windowID)
                record[8] = 1
                guard postRecord(&process, &record) == .success else {
                    return false
                }
                record[8] = 2
                return postRecord(&process, &record) == .success
            }
        )
    }

    /// Keep yabai's inter-event spacing, but never activate an obsolete target
    /// after waiting. Do not restore the old window: that could steal focus from
    /// a newer user action. All callbacks execute synchronously on the worker.
    static func performFocus(
        switchingWithinApplication: Bool,
        isCurrent: () -> Bool,
        deactivate: () -> Bool,
        wait: () -> Void,
        activate: () -> Bool
    ) -> Bool {
        guard isCurrent() else {
            return false
        }
        if switchingWithinApplication {
            guard deactivate() else {
                return false
            }
            wait()
            guard isCurrent() else {
                return false
            }
        }
        return activate()
    }

    private static func baseRecord(windowID: CGWindowID) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 0xF8)
        record[4] = 0xF8
        withUnsafeBytes(of: windowID) { record.replaceSubrange(0x3C ..< 0x40, with: $0) }
        return record
    }

    private static func stateRecord(windowID: CGWindowID, state: UInt8) -> [UInt8] {
        var record = baseRecord(windowID: windowID)
        record[8] = 0x0D
        record[0x8A] = state
        return record
    }

    private static func keyRecord(windowID: CGWindowID) -> [UInt8] {
        var record = baseRecord(windowID: windowID)
        record[0x3A] = 0x10
        record.replaceSubrange(0x20 ..< 0x30, with: repeatElement(UInt8(0xFF), count: 0x10))
        return record
    }
}
