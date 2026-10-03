// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import LRUCache
import os.log

struct EventTransformerContext {
    var device: Device?
    var deferredEventSink: ((CGEvent) -> Void)?
    /// Reconcile route ownership after a timer resumes a suspended pipeline.
    var didTransformDeferredEvent: (() -> Void)?

    init(device: Device?, deferredEventSink: ((CGEvent) -> Void)? = nil) {
        self.device = device
        self.deferredEventSink = deferredEventSink
    }
}

struct EventTransformerResolution {
    var transformer: EventTransformer
    var context: EventTransformerContext
    var didTransform: (() -> Void)?

    init(
        transformer: EventTransformer,
        context: EventTransformerContext,
        didTransform: (() -> Void)? = nil
    ) {
        self.transformer = transformer
        self.context = context
        self.didTransform = didTransform
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        transform(event) { $0.post(tap: .cgSessionEventTap) }
    }

    func transform(_ event: CGEvent, deferredEventSink: @escaping (CGEvent) -> Void) -> CGEvent? {
        defer {
            didTransform?()
        }

        var context = context
        context.deferredEventSink = deferredEventSink
        context.didTransformDeferredEvent = didTransform
        return transformer.transform(event, in: context)
    }
}

protocol EventTransformer {
    /// Whether this stage currently needs movement/drag input.
    var handlesPointerMotion: Bool { get }
    /// Whether this event may be retained and resumed through the remaining stages.
    func needsDeferredEventContinuation(for event: CGEvent) -> Bool
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent?
}

extension EventTransformer {
    /// New transformers receive all input unless they explicitly opt out.
    var handlesPointerMotion: Bool {
        true
    }

    func needsDeferredEventContinuation(for _: CGEvent) -> Bool {
        false
    }
}

/// Adopted by stateful transformers that must continue receiving events until
/// the physical interaction they claimed has ended.
protocol EventTransformerInteractionTracking: AnyObject {
    var hasActiveInteraction: Bool { get }
}

enum LogitechControlEventHandlingResult {
    case notHandled
    case handled
    case handledAllowingSyntheticFallback
    case handledDeferringSyntheticFallback

    var suppressesSyntheticFallback: Bool {
        self == .handled || self == .handledDeferringSyntheticFallback
    }
}

protocol LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult
}

/// Adopted by stateful transformers that can abandon one Logitech control
/// stream when its HID++ monitor disappears before reporting the release.
protocol LogitechControlInteractionCanceling {
    @discardableResult
    func cancelLogitechControlInteraction(_ context: LogitechEventContext) -> Bool
}

extension [EventTransformer]: EventTransformer {
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        var event = event

        for (index, transformer) in enumerated() {
            // Earlier stages can rewrite the event type, so decide at each stage.
            guard !event.type.isPointerMotion || transformer.handlesPointerMotion else {
                continue
            }
            var transformerContext = context
            if transformer.needsDeferredEventContinuation(for: event),
               let finalSink = context.deferredEventSink {
                // Retain only the tail: retaining the buffering stage would form
                // a cycle. Keep every later stage since replay can change type.
                let remainingTransformers = Array(dropFirst(index + 1))
                transformerContext.deferredEventSink = { deferredEvent in
                    defer { context.didTransformDeferredEvent?() }
                    if let transformedEvent = remainingTransformers.transform(deferredEvent, in: context) {
                        finalSink(transformedEvent)
                    }
                }
            }
            guard let transformedEvent = transformer.transform(event, in: transformerContext) else {
                return nil
            }
            event = transformedEvent
        }

        return event
    }
}

extension [EventTransformer]: LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        for eventTransformer in self {
            let result = (eventTransformer as? LogitechControlEventHandling)?.handleLogitechControlEvent(context)
                ?? .notHandled
            if result != .notHandled {
                return result
            }
        }

        return .notHandled
    }
}

protocol Deactivatable {
    func deactivate()
    func reactivate()
}

extension Deactivatable {
    func deactivate() {}
    func reactivate() {}
}

extension [EventTransformer]: Deactivatable {
    func deactivate() {
        for eventTransformer in self {
            if let eventTransformer = eventTransformer as? Deactivatable {
                eventTransformer.deactivate()
            }
        }
    }

    func reactivate() {
        for eventTransformer in self {
            if let eventTransformer = eventTransformer as? Deactivatable {
                eventTransformer.reactivate()
            }
        }
    }
}
