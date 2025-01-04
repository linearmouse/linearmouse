// MIT License
// Copyright (c) 2021-2025 LinearMouse

// https://github.com/sindresorhus/Defaults/blob/54f970b9d7c269193756599c7ae5318878dcab1a/Sources/Defaults/util.swift

/*
 MIT License

 Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (sindresorhus.com)

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import Foundation

final class AssociatedObject<T: Any> {
    subscript(index: Any) -> T? {
        get {
            // swiftlint:disable force_cast
            objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as! T?
        } set {
            objc_setAssociatedObject(
                index,
                Unmanaged.passUnretained(self).toOpaque(),
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/**
 Causes a given target object to live at least as long as a given owner object.
 */
final class LifetimeAssociation {
    private class ObjectLifetimeTracker {
        var object: AnyObject?
        var deinitHandler: () -> Void

        init(for weaklyHeldObject: AnyObject, deinitHandler: @escaping () -> Void) {
            object = weaklyHeldObject
            self.deinitHandler = deinitHandler
        }

        deinit {
            deinitHandler()
        }
    }

    private static let associatedObjects = AssociatedObject<[ObjectLifetimeTracker]>()
    private weak var wrappedObject: ObjectLifetimeTracker?
    private weak var owner: AnyObject?

    /**
     Causes the given target object to live at least as long as either the given owner object or the resulting `LifetimeAssociation`, whichever is deallocated first.
     When either the owner or the new `LifetimeAssociation` is destroyed, the given deinit handler, if any, is called.
     ```
     class Ghost {
     var association: LifetimeAssociation?
     func haunt(_ host: Furniture) {
     association = LifetimeAssociation(of: self, with: host) { [weak self] in
     // Host has been deinitialized
     self?.haunt(seekHost())
     }
     }
     }
     let piano = Piano()
     Ghost().haunt(piano)
     // The Ghost will remain alive as long as `piano` remains alive.
     ```
     - Parameter target: The object whose lifetime will be extended.
     - Parameter owner: The object whose lifetime extends the target object's lifetime.
     - Parameter deinitHandler: An optional closure to call when either `owner` or the resulting `LifetimeAssociation` is deallocated.
     */
    init(of target: AnyObject, with owner: AnyObject, deinitHandler: @escaping () -> Void = {}) {
        let wrappedObject = ObjectLifetimeTracker(for: target, deinitHandler: deinitHandler)

        let associatedObjects = LifetimeAssociation.associatedObjects[owner] ?? []
        LifetimeAssociation.associatedObjects[owner] = associatedObjects + [wrappedObject]

        self.wrappedObject = wrappedObject
        self.owner = owner
    }

    /**
     Invalidates the association, unlinking the target object's lifetime from that of the owner object. The provided deinit handler is not called.
     */
    func cancel() {
        wrappedObject?.deinitHandler = {}
        invalidate()
    }

    deinit {
        invalidate()
    }

    private func invalidate() {
        guard
            let owner = owner,
            let wrappedObject = wrappedObject,
            var associatedObjects = LifetimeAssociation.associatedObjects[owner],
            let wrappedObjectAssociationIndex = associatedObjects.firstIndex(where: { $0 === wrappedObject })
        else {
            return
        }

        associatedObjects.remove(at: wrappedObjectAssociationIndex)
        LifetimeAssociation.associatedObjects[owner] = associatedObjects
        self.owner = nil
    }
}
