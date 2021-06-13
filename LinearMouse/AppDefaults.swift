//
//  Settings.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import SwiftUI
import AppStorage

class AppDefaults: ObservableObject {
    public static let shared = AppDefaults()

    @AppStorageCompat(wrappedValue: true, "reverseScrollingOn") var reverseScrollingOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: true, "linearScrollingOn") var linearScrollingOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: 3, "scrollLines") var scrollLines: Int {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorageCompat(wrappedValue: true, "linearMovementOn") var linearMovementOn: Bool {
        willSet {
            objectWillChange.send()
        }
    }
}
