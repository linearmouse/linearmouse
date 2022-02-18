//
//  MomentumPhaseFix.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/18.
//

import Foundation

class MomentumPhaseFix: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)
        guard view.momentumPhase == .begin else {
            return event
        }

        if let cfData = event.__data(allocator: kCFAllocatorDefault) {
            var data = cfData as Data
            var dataModified = false
            if data.count == 468 {
                data.withUnsafeMutableBytes {
                    let offset = 170
                    let value = $0.load(fromByteOffset: offset, as: Int16.self)
                    // TODO: Only the sign has been fixed.
                    if value.signum() == view.deltaY.signum() {
                        $0.storeBytes(of: -value, toByteOffset: offset, as: Int16.self)
                        dataModified = true
                    }
                }
            }
            if dataModified {
                if let event = CGEvent(withDataAllocator: kCFAllocatorDefault, data: data as CFData) {
                    return event
                }
            }
        }

        return event
    }
}
