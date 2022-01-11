//
//  AutoUpdateManager.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/1/11.
//

import Foundation
import Sparkle

class AutoUpdateManager: NSObject {
    static let shared = AutoUpdateManager()

    private var _controller: SPUStandardUpdaterController! = nil
    var controller: SPUStandardUpdaterController {
        _controller
    }

    override init() {
        super.init()
        _controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}
