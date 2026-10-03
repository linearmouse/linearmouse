// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Configuration {
    /// Save the original bytes (including comments) before replacing the file.
    /// Resolve source symlinks by reading data so the backup is independent.
    mutating func migrateLegacyGestureButtons(persistingTo url: URL) throws {
        var migrated = self
        guard migrated.migrateLegacyGestureButtons() else {
            return
        }
        let backup = url.appendingPathExtension("before-gesture-migration")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try Data(contentsOf: url).write(to: backup, options: .withoutOverwriting)
        }
        try migrated.dump(to: url)
        self = migrated
    }

    /// Called only by startup loading. Removing each migrated legacy field
    /// prevents duplicate migration on subsequent launches.
    @discardableResult
    mutating func migrateLegacyGestureButtons() -> Bool {
        typealias Mapping = Scheme.Buttons.Mapping
        var inheritedTriggers = [Mapping.Trigger]()
        var changed = false
        let originalSchemes = schemes
        var migratedSchemes = [Scheme]()

        for (index, original) in originalSchemes.enumerated() {
            var scheme = original
            guard let gesture = scheme.buttons.$gesture else {
                migratedSchemes.append(scheme)
                continue
            }

            let migrationStart = migratedSchemes.count
            var migrated = [Mapping]()
            if gesture.enabled == true, let trigger = gesture.trigger?.effectiveTrigger {
                let mapping = Mapping(
                    trigger: trigger,
                    outcomes: .init(swipe: .init(
                        up: gesture.actions.up.mappingAction(default: .missionControl),
                        down: gesture.actions.down.mappingAction(default: .appExpose),
                        left: gesture.actions.left.mappingAction(default: .spaceLeft),
                        right: gesture.actions.right.mappingAction(default: .spaceRight)
                    ))
                )
                // Keep unsupported legacy inputs intact rather than silently
                // deleting a configuration the new recognizer cannot execute.
                guard mapping.valid else {
                    migratedSchemes.append(scheme)
                    continue
                }
                migrated.append(mapping)
            }

            if !inheritedTriggers.isEmpty {
                // Replacing a legacy gesture must restore the ordinary mappings
                // underneath it, not disable those mappings along with the gesture.
                let resets = inheritedTriggers.map { trigger in
                    Mapping(trigger: trigger, outcomes: .init(swipe: .init(
                        up: .arg0(.auto), down: .arg0(.auto), left: .arg0(.auto), right: .arg0(.auto)
                    )))
                }
                migratedSchemes.append(Scheme(if: scheme.if, buttons: .init(mappings: resets)))
                for previous in originalSchemes[..<index] {
                    let mappings = (previous.buttons.mappings ?? []).filter { mapping in
                        guard let trigger = mapping.effectiveTrigger else {
                            return false
                        }
                        return inheritedTriggers.contains { $0.isEquivalent(to: trigger) }
                    }
                    guard !mappings.isEmpty else {
                        continue
                    }
                    // Restore only where both original rules apply. This uses
                    // the existing scheme format, without adding mapping options.
                    let conditions = Self.gestureMigrationIntersection(previous.if, scheme.if)
                    guard conditions?.isEmpty != true else {
                        continue
                    }
                    let restoration = Scheme(if: conditions, buttons: .init(mappings: mappings))
                    if migratedSchemes.last?.if == conditions {
                        restoration.merge(into: &migratedSchemes[migratedSchemes.count - 1])
                    } else {
                        migratedSchemes.append(restoration)
                    }
                }
            }
            if let trigger = migrated.first?.trigger,
               !inheritedTriggers.contains(where: { $0.isEquivalent(to: trigger) }) {
                inheritedTriggers.append(trigger)
            }

            // Preserve explicitly configured outcomes when the same trigger
            // already exists, including immediate/repeat/hold/remap actions.
            var existingMappings = [Mapping]()
            for existing in scheme.buttons.mappings ?? [] {
                if let existingTrigger = existing.effectiveTrigger,
                   let matching = migrated.firstIndex(where: {
                       $0.trigger?.isEquivalent(to: existingTrigger) == true
                   }) {
                    var normalized = existing
                    normalized.normalizeAsStructured()
                    var merged = migrated.remove(at: matching)
                    merged.mergeOutcomes(from: normalized)
                    existingMappings.append(merged)
                } else {
                    existingMappings.append(existing)
                }
            }
            migrated += existingMappings
            if !migrated.isEmpty {
                scheme.buttons.mappings = migrated
            }
            scheme.buttons.$gesture = nil
            // Keep adjacent rules for the same scope together so the settings
            // editor sees the original settings as well as restored mappings.
            if migratedSchemes.count > migrationStart, migratedSchemes.last?.if == scheme.if {
                scheme.merge(into: &migratedSchemes[migratedSchemes.count - 1])
            } else {
                migratedSchemes.append(scheme)
            }
            changed = true
        }
        if changed {
            schemes = migratedSchemes
        }
        return changed
    }
}

private extension Optional where Wrapped == Scheme.Buttons.Gesture.GestureAction {
    func mappingAction(default fallback: Wrapped) -> Scheme.Buttons.Mapping.Action {
        let action = self ?? fallback
        // The two enums deliberately share their serialized action names.
        return .arg0(Scheme.Buttons.Mapping.Action.Arg0(rawValue: action.rawValue)!)
    }
}

private extension Configuration {
    enum GestureMigrationConditionError: Error {
        case disjoint
    }

    /// Scheme conditions are OR lists; each pair's intersection is an AND.
    // swiftlint:disable:next discouraged_optional_collection
    static func gestureMigrationIntersection(_ lhs: [Scheme.If]?, _ rhs: [Scheme.If]?) -> [Scheme.If]? {
        guard let lhs else {
            return rhs
        }
        guard let rhs else {
            return lhs
        }
        return lhs.flatMap { left in
            rhs.compactMap { right in
                try? gestureMigrationIntersection(left, right)
            }
        }
    }

    static func gestureMigrationIntersection(_ lhs: Scheme.If, _ rhs: Scheme.If) throws -> Scheme.If {
        func intersect<T: Equatable>(_ lhs: T?, _ rhs: T?) throws -> T? {
            if let lhs, let rhs, lhs != rhs {
                throw GestureMigrationConditionError.disjoint
            }
            return lhs ?? rhs
        }

        var device = lhs.device ?? rhs.device
        if let left = lhs.device, let right = rhs.device {
            device = try DeviceMatcher(
                vendorID: intersect(left.vendorID, right.vendorID),
                productID: intersect(left.productID, right.productID),
                productName: intersect(left.productName, right.productName),
                serialNumber: intersect(left.serialNumber, right.serialNumber),
                category: left.category ?? right.category
            )
            if let leftCategories = left.category, let rightCategories = right.category {
                let common = leftCategories.filter { rightCategories.contains($0) }
                guard !common.isEmpty else {
                    throw GestureMigrationConditionError.disjoint
                }
                device?.category = common
            }
        }
        return try Scheme.If(
            device: device,
            app: intersect(lhs.app, rhs.app),
            parentApp: intersect(lhs.parentApp, rhs.parentApp),
            groupApp: intersect(lhs.groupApp, rhs.groupApp),
            processName: intersect(lhs.processName, rhs.processName),
            processPath: intersect(lhs.processPath, rhs.processPath),
            display: intersect(lhs.display, rhs.display)
        )
    }
}
