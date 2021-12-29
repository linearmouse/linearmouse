//
//  EventTests.swift
//  LinearMouseUnitTests
//
//  Created by Jiahao Lu on 2022/1/7.
//

import XCTest
@testable import LinearMouse

class EventTests: XCTestCase {
    func testEvent() throws {
        let context = JSContext()!
        Assert().registerInContext(context)
        Event().registerInContext(context)
        context.evaluateScript(#"""
            assert(!('EventTargetShim' in globalThis));
            let fired;
            const target = new EventTarget();
            target.addEventListener('mousedown', (e) => {
                e.preventDefault();
                fired = true;
            });
            {
                const event = new MouseEvent('mousedown', { cancelable: true });
                assert(!target.dispatchEvent(event));
                assert(fired);
            }
            {
                const event = new WheelEvent('mousedown', { cancelable: true });
                assert(!target.dispatchEvent(event));
                assert(fired);
            }
        """#)
        XCTAssertNil(context.exception)
    }
}
