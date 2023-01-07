// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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

public func postSystemDefinedKey(_ key: SystemDefinedKey) {
    let down = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: 0xA00),
                                  timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                  data1: (key.rawValue << 16) | (0xA << 8), data2: -1)
    let up = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: 0xB00),
                                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                data1: (key.rawValue << 16) | (0xB << 8), data2: -1)
    down?.cgEvent?.post(tap: .cgSessionEventTap)
    up?.cgEvent?.post(tap: .cgSessionEventTap)
}
