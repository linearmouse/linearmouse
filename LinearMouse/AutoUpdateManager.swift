//
//  AutoUpdateManager.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/1/11.
//

import Foundation
import Sparkle
import Version

class AutoUpdateManager: NSObject {
    static let shared = AutoUpdateManager()

    private var _controller: SPUStandardUpdaterController! = nil
    var controller: SPUStandardUpdaterController {
        _controller
    }

    override init() {
        super.init()
        _controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }
}

extension AutoUpdateManager: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        AppDefaults.shared.betaChannelOn ? ["beta"] :  []
    }

    func versionComparator(for updater: SPUUpdater) -> SUVersionComparison? {
        SemanticVersioningComparator()
    }
}

class SemanticVersioningComparator: SUVersionComparison {
    func compareVersion(_ versionA: String, toVersion versionB: String) -> ComparisonResult {
        do {
            let a = try Version(versionA)
            let b = try Version(versionB)
            if a < b {
                return .orderedAscending
            } else if a > b {
                return .orderedDescending
            }
            return .orderedSame
        } catch {
            return .orderedSame
        }
    }
}
