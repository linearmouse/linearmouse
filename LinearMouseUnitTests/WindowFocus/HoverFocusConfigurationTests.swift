// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class HoverFocusConfigurationTests: XCTestCase {
    func testMouseOnlyAndTargetApplicationOverrideRoundTrip() throws {
        let configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"if":{"device":{"category":"mouse"}},"pointer":{"focusFollowsMouse":true}},
          {"if":{"device":{"category":"mouse"},"app":"com.example.excluded"},
           "pointer":{"focusFollowsMouse":false}}
        ]}
        """#)
        let mouse = DeviceMatcher(category: .mouse)
        let trackpad = DeviceMatcher(category: .trackpad)
        XCTAssertTrue(try XCTUnwrap(
            configuration.matchScheme(withDeviceMatcher: mouse, withApp: "com.example.editor")
                .pointer
                .focusFollowsMouse
        ))
        XCTAssertFalse(try XCTUnwrap(
            configuration.matchScheme(withDeviceMatcher: mouse, withApp: "com.example.excluded")
                .pointer
                .focusFollowsMouse
        ))
        XCTAssertNil(configuration.matchScheme(withDeviceMatcher: trackpad, withApp: "com.example.editor")
            .pointer
            .focusFollowsMouse)
        XCTAssertEqual(try Configuration.load(from: configuration.dump()), configuration)
    }

    func testOmittedSettingInheritsAndSpecificDeviceCanOptOut() throws {
        let configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"if":{"device":{"category":"mouse"}},"pointer":{"focusFollowsMouse":true}},
          {"if":{"app":"com.example.editor"},"pointer":{"disableAcceleration":true}},
          {"if":{"device":{"vendorID":1,"productID":2}},"pointer":{"focusFollowsMouse":false}}
        ]}
        """#)
        var mouse = DeviceMatcher(category: .mouse)
        XCTAssertTrue(try XCTUnwrap(
            configuration.matchScheme(withDeviceMatcher: mouse, withApp: "com.example.editor")
                .pointer
                .focusFollowsMouse
        ))
        mouse.vendorID = 1
        mouse.productID = 2
        XCTAssertFalse(try XCTUnwrap(
            configuration.matchScheme(withDeviceMatcher: mouse, withApp: "com.example.editor")
                .pointer
                .focusFollowsMouse
        ))
    }

    func testDefaultOffDoesNotAddSynchronousTransformerMotionWork() throws {
        let old = try Configuration.load(from: #"{"schemes":[{"pointer":{"disableAcceleration":true}}]}"#)
        XCTAssertNil(old.matchScheme(withDeviceMatcher: .init(category: .mouse)).pointer.focusFollowsMouse)
        var scheme = Scheme()
        scheme.pointer.focusFollowsMouse = true
        // Hover observation is independent from synchronous event transformation.
        XCTAssertTrue(PointerMotionRequirements(configuration: .init(schemes: [scheme])).isEmpty)
    }
}
