// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit
import Foundation

// See NX_KEYTYPE_SOUND_UP
public enum SystemDefinedKey: Int {
    case soundUp = 0,
         soundDown,
         brightnessUp,
         brightnessDown,
         capsLock,
         help = 5,
         power,
         mute,
         arrowUp,
         arrowDown,
         numLock = 10,
         contrastUp,
         contrastDown,
         launchPanel,
         eject,
         vidmirror = 15,
         play,
         next,
         previous,
         fast,
         rewind = 20,
         illuminationUp,
         illuminationDown,
         illuminationToggle
}

public func postSystemDefinedKey(_ key: SystemDefinedKey, keyDown: Bool) {
    var iter: mach_port_t = 0

    guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOHIDSystemClass), &iter) ==
        KERN_SUCCESS else {
        return
    }
    defer { IOObjectRelease(iter) }

    let service = IOIteratorNext(iter)
    guard service != 0 else {
        return
    }
    defer { IOObjectRelease(service) }

    var handle: io_connect_t = .zero
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle) == KERN_SUCCESS else {
        return
    }
    defer { IOServiceClose(handle) }

    var event = NXEventData()
    event.compound.subType = Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
    event.compound.misc.L.0 = Int32(key.rawValue) << 16 | (keyDown ? NX_KEYDOWN : NX_KEYUP) << 8
    IOHIDPostEvent(handle, UInt32(NX_SYSDEFINED), .init(x: 0, y: 0), &event,
                   UInt32(kNXEventDataVersion), IOOptionBits(0), IOOptionBits(kIOHIDSetGlobalEventFlags))
}

public func postSystemDefinedKey(_ key: SystemDefinedKey) {
    postSystemDefinedKey(key, keyDown: true)
    postSystemDefinedKey(key, keyDown: false)
}
