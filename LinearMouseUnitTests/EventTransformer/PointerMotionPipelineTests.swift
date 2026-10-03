// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerMotionPipelineTests: XCTestCase {
    private final class WheelOnly: EventTransformer {
        var handlesPointerMotion: Bool {
            false
        }

        var continuationRequests = 0
        func needsDeferredEventContinuation(for _: CGEvent) -> Bool {
            continuationRequests += 1
            return true
        }

        var calls = 0
        func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
            calls += 1
            return event
        }
    }

    private struct Rewrite: EventTransformer {
        let type: CGEventType
        func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
            event.type = type
            return event
        }
    }

    func testMotionSkipsUnrelatedTransformersButUsesRewrittenEventType() throws {
        let wheel = WheelOnly()
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = .leftMouseDragged
        let context = EventTransformerContext(device: nil) { _ in }
        XCTAssertNotNil(([wheel] as [EventTransformer]).transform(event, in: context))
        XCTAssertEqual(wheel.calls, 0)
        XCTAssertEqual(wheel.continuationRequests, 0)

        let pipeline: [EventTransformer] = [Rewrite(type: .scrollWheel), wheel]
        XCTAssertNotNil(pipeline.transform(event, in: context))
        XCTAssertEqual(wheel.calls, 1)
        XCTAssertEqual(wheel.continuationRequests, 1)
    }

    func testDeferredContinuationStillIncludesTransformersSkippedForOriginalMotion() throws {
        final class Deferred: EventTransformer {
            func needsDeferredEventContinuation(for _: CGEvent) -> Bool {
                true
            }

            var sink: ((CGEvent) -> Void)?
            func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
                sink = context.deferredEventSink
                return event
            }
        }
        let deferred = Deferred()
        let wheel = WheelOnly()
        var delivered = 0
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = .mouseMoved
        let pipeline: [EventTransformer] = [deferred, wheel]
        let context = EventTransformerContext(device: nil) { _ in delivered += 1 }
        _ = pipeline.transform(event, in: context)
        XCTAssertEqual(wheel.calls, 0)
        event.type = .scrollWheel
        deferred.sink?(event)
        XCTAssertEqual(wheel.calls, 1)
        XCTAssertEqual(delivered, 1)
    }

    func testDeferredConsumptionStillReconcilesOwnership() throws {
        final class Deferred: EventTransformer {
            func needsDeferredEventContinuation(for _: CGEvent) -> Bool {
                true
            }

            var sink: ((CGEvent) -> Void)?
            func transform(_: CGEvent, in context: EventTransformerContext) -> CGEvent? {
                sink = context.deferredEventSink
                return nil
            }
        }
        struct Consume: EventTransformer {
            func transform(_: CGEvent, in _: EventTransformerContext) -> CGEvent? {
                nil
            }
        }
        let deferred = Deferred()
        let pipeline: [EventTransformer] = [deferred, Consume()]
        var completions = 0
        let resolution = EventTransformerResolution(transformer: pipeline, context: .init(device: nil)) {
            completions += 1
        }
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = .leftMouseDown
        XCTAssertNil(resolution.transform(event) { _ in XCTFail("The event was consumed") })
        XCTAssertEqual(completions, 1)
        try XCTUnwrap(deferred.sink)(event)
        XCTAssertEqual(completions, 2)
    }
}
