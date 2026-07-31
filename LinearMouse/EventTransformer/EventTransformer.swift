// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import LRUCache
import os.log

struct EventTransformerContext {
    var device: Device?
    var deferredEventSink: ((CGEvent) -> Void)?

    init(device: Device?, deferredEventSink: ((CGEvent) -> Void)? = nil) {
        self.device = device
        self.deferredEventSink = deferredEventSink
    }
}

struct EventTransformerResolution {
    var transformer: EventTransformer
    var context: EventTransformerContext

    func transform(_ event: CGEvent) -> CGEvent? {
        var context = context
        context.deferredEventSink = { $0.post(tap: .cgSessionEventTap) }
        return transformer.transform(event, in: context)
    }
}

protocol EventTransformer {
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent?
}

/// Adopted by transformers that can emit an event after `transform` returns.
///
/// The array transformer provides those events with a continuation through the
/// remaining transformers before they are posted back to the session.
protocol DeferredEventTransformer {}

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

extension [EventTransformer]: EventTransformer {
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        var event: CGEvent? = event

        for (index, eventTransformer) in enumerated() {
            event = event.flatMap {
                var transformerContext = context

                if eventTransformer is DeferredEventTransformer,
                   let finalSink = context.deferredEventSink {
                    // Capture only the tail. A deferred transformer may retain this
                    // continuation while a timer is active, so capturing the full
                    // array here would create a temporary retain cycle.
                    let remainingTransformers = Array(dropFirst(index + 1))
                    transformerContext.deferredEventSink = { deferredEvent in
                        if let transformedEvent = remainingTransformers.transform(deferredEvent, in: context) {
                            finalSink(transformedEvent)
                        }
                    }
                }

                return eventTransformer.transform($0, in: transformerContext)
            }
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
