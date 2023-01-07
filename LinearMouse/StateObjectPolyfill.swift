// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import PublishedObject
import SwiftUI

// Modified from: https://gist.github.com/Amzd/8f0d4d94fcbb6c9548e7cf0c1493eaff

/// A property wrapper type that instantiates an observable object.
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty
    where ObjectType.ObjectWillChangePublisher == ObservableObjectPublisher {
    /// Wrapper that helps with initialising without actually having an ObservableObject yet
    private class ObservedObjectWrapper: ObservableObject {
        @PublishedObject var wrappedObject: ObjectType?
        init() {}
    }

    private var thunk: () -> ObjectType
    @ObservedObject private var observedObject = ObservedObjectWrapper()
    @State private var state = ObservedObjectWrapper()

    public var wrappedValue: ObjectType {
        if state.wrappedObject == nil {
            // There is no State yet so we need to initialise the object
            state.wrappedObject = thunk()
            // and start observing it
            observedObject.wrappedObject = state.wrappedObject
        } else if observedObject.wrappedObject == nil {
            // Retrieve the object from State and observe it in ObservedObject
            observedObject.wrappedObject = state.wrappedObject
        }
        return state.wrappedObject!
    }

    public var projectedValue: ObservedObject<ObjectType>.Wrapper {
        ObservedObject(wrappedValue: wrappedValue).projectedValue
    }

    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) {
        self.thunk = thunk
    }

    public mutating func update() {
        // Not sure what this does but we'll just forward it
        _state.update()
        _observedObject.update()
    }
}
