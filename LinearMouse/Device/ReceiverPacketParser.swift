// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

enum ReceiverPacketParser {
    static func activePointingSlot(from report: Data) -> UInt8? {
        let bytes = [UInt8](report)
        guard bytes.count >= 3 else {
            return nil
        }

        guard [UInt8(0x20), UInt8(0x21)].contains(bytes[0]),
              (1 ... 6).contains(Int(bytes[1])) else {
            return nil
        }

        guard bytes[2] == 0x02 || bytes[2] == 0x05 else {
            return nil
        }

        return bytes[1]
    }
}
