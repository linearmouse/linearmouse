// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Carbon
import Combine

/// Caches the physical shortcuts AppKit accepts for Command-modified menu key equivalents.
/// Call `refresh()` on the main thread before using the cache from an event thread.
public final class KeyEquivalentResolver {
    public struct Shortcut: Equatable {
        public let keyCode: CGKeyCode
        public let modifierFlags: CGEventFlags

        public init(keyCode: CGKeyCode, modifierFlags: CGEventFlags) {
            self.keyCode = keyCode
            self.modifierFlags = modifierFlags
        }
    }

    private let resolve: () -> [String: Shortcut]
    private let lock = NSLock()
    private var shortcuts: [String: Shortcut] = [:]
    private var generation = 0
    private var subscription: AnyCancellable?

    public convenience init(keyEquivalents: [String]) {
        let notifications = DistributedNotificationCenter.default
        let changes = Publishers.Merge(
            notifications.publisher(for: .init(kTISNotifySelectedKeyboardInputSourceChanged as String)),
            notifications.publisher(for: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
        )
        .map { _ in () }
        .eraseToAnyPublisher()

        self.init(resolve: { Self.resolve(keyEquivalents: keyEquivalents) }, inputSourceChanges: changes)
    }

    init(resolve: @escaping () -> [String: Shortcut], inputSourceChanges: AnyPublisher<Void, Never>) {
        self.resolve = resolve
        // Never send a key resolved for the previous layout while AppKit catches up.
        let invalidateCache: (()) -> Void = { [weak self] _ in self?.invalidate() }
        subscription = inputSourceChanges
            .handleEvents(receiveOutput: invalidateCache)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
    }

    /// Resolving uses AppKit and Text Input Source Services, neither of which belongs in an event tap.
    public func refresh() {
        precondition(Thread.isMainThread)
        let currentGeneration = lock.withLock { generation }
        let updated = resolve()
        lock.withLock {
            if currentGeneration == generation {
                shortcuts = updated
            }
        }
    }

    private func invalidate() {
        lock.withLock {
            generation += 1
            shortcuts = [:]
        }
    }

    public func shortcut(for keyEquivalent: String) -> Shortcut? {
        lock.withLock { shortcuts[keyEquivalent] }
    }

    private final class Target: NSObject {
        var matchedKeyEquivalent: String?

        @objc func match(_ item: NSMenuItem) {
            matchedKeyEquivalent = item.representedObject as? String
        }
    }

    static func resolve(keyEquivalents: [String]) -> [String: Shortcut] {
        precondition(Thread.isMainThread)
        var hotKeys: Unmanaged<CFArray>?
        guard #available(macOS 12, *),
              let source = CGEventSource(stateID: .privateState),
              CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]] else {
            return [:]
        }
        let reserved = reservedShortcuts(in: entries)

        let target = Target()
        let menu = NSMenu(title: "LinearMouse key equivalents")
        menu.autoenablesItems = false
        for (index, equivalent) in keyEquivalents.enumerated() {
            // Internal titles keep user menu-title overrides out of this local probe.
            let item = NSMenuItem(
                title: "__LinearMouseKeyEquivalent_\(index)__",
                action: #selector(Target.match(_:)),
                keyEquivalent: equivalent
            )
            item.keyEquivalentModifierMask = .command
            item.allowsAutomaticKeyEquivalentLocalization = true
            item.allowsAutomaticKeyEquivalentMirroring = false
            item.target = target
            item.representedObject = equivalent
            item.isEnabled = true
            menu.addItem(item)
        }

        return resolve(keyEquivalents: keyEquivalents, reserved: reserved) { shortcut in
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: shortcut.keyCode,
                keyDown: true
            ) else {
                return nil
            }
            event.flags = shortcut.modifierFlags
            event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(source.keyboardType))
            guard let nsEvent = NSEvent(cgEvent: event) else {
                return nil
            }
            target.matchedKeyEquivalent = nil
            // Only dispatch to our detached menu and target. Never post candidate events to macOS.
            guard menu.performKeyEquivalent(with: nsEvent) else {
                return nil
            }
            return target.matchedKeyEquivalent
        }
    }

    static func resolve(
        keyEquivalents: [String],
        reserved: [Shortcut],
        matching: (Shortcut) -> String?
    ) -> [String: Shortcut] {
        // Main typing keys, including ISO and JIS. Prefer these over the numeric keypad.
        let keyCodes = Array(CGKeyCode(0) ..< 0x33) + [CGKeyCode(kVK_JIS_Yen), CGKeyCode(kVK_JIS_Underscore)]
        let modifierSets: [CGEventFlags] = [
            .maskCommand, [.maskCommand, .maskShift],
            [.maskCommand, .maskAlternate], [.maskCommand, .maskShift, .maskAlternate]
        ]
        var result: [String: Shortcut] = [:]
        let equivalents = Set(keyEquivalents)
        for modifiers in modifierSets {
            for keyCode in keyCodes {
                let shortcut = Shortcut(keyCode: keyCode, modifierFlags: modifiers)
                guard !reserved.contains(shortcut),
                      let equivalent = matching(shortcut),
                      equivalents.contains(equivalent), result[equivalent] == nil else {
                    continue
                }
                result[equivalent] = shortcut
                if result.count == equivalents.count {
                    return result
                }
            }
        }
        return result
    }

    static func reservedShortcuts(in entries: [[String: Any]]) -> [Shortcut] {
        entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? UInt16,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? UInt32 else {
                return nil
            }
            var flags: CGEventFlags = []
            for (carbon, cg): (Int, CGEventFlags) in [
                (cmdKey, .maskCommand), (shiftKey, .maskShift),
                (optionKey, .maskAlternate), (controlKey, .maskControl)
            ] where modifiers & UInt32(carbon) != 0 {
                flags.insert(cg)
            }
            return Shortcut(keyCode: code, modifierFlags: flags)
        }
    }
}
