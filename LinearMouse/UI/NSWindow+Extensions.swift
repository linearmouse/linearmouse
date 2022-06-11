//
//  NSWindow+Show.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/11.
//

import Foundation
import SwiftUI

extension NSWindow {
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
