//
//  Assert.swift
//  LinearMouseUnitTests
//
//  Created by Jiahao Lu on 2022/1/7.
//

import Foundation
@testable import LinearMouse

private let assertScript = #"""
(function () {
    'use strict';

    globalThis.AssertionError = class AssertionError extends Error {
        constructor(message) {
            super(message)
            this.name = this.constructor.name;
        }
    };

    globalThis.assert = function assert(value, message) {
        if (value) return;
        if (message === void 0) {
            message = `${String(value)} == true`;
        }
        throw new AssertionError(String(message));
    };
})();
"""#

class Assert: Library {
    func registerInContext(_ context: JSContext) {
        context.evaluateScript(assertScript)
        assert(context.exception == nil, String(describing: context.exception))
    }
}
