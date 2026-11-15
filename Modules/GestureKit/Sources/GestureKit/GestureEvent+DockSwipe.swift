// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Darwin

/// The Dock gesture driven by a dock swipe event.
public enum DockSwipeMotion: Int64, Sendable {
    /// Switch between desktop spaces, like a horizontal three/four-finger swipe.
    case horizontal = 1
    /// Mission Control / App Exposé, like a vertical three/four-finger swipe.
    case vertical = 2
}

/// Synthesizes the interactive trackpad swipe the Dock uses to switch spaces.
///
/// Unlike `missionControl.spaceLeft`, which jumps a whole space at once, the Dock
/// follows `progress` while the gesture is in flight and decides on `.ended`
/// whether to finish the switch or snap back, based on how far and how fast
/// the gesture moved. `.cancelled` always snaps back.
public extension GestureEvent {
    /// - Parameters:
    ///   - progress: Cumulative offset since the gesture began. One unit is one full space;
    ///     the sign selects the direction.
    ///   - velocity: Exit velocity, only meaningful when the gesture ends.
    convenience init?(
        dockSwipeSource: CGEventSource?,
        motion: DockSwipeMotion,
        phase: CGSGesturePhase,
        progress: Double,
        velocity: Double = 0
    ) {
        let events: [CGEvent]
        if #available(macOS 27.0, *) {
            // The Dock ignores the CGEvent fields from macOS 27 and reads the
            // IOHIDEvent attached to the event instead.
            events = DockSwipeHIDEvent.cgEvents(
                source: dockSwipeSource,
                motion: motion,
                phase: phase,
                progress: progress,
                velocity: velocity
            )
        } else {
            events = DockSwipeFieldEvent.cgEvents(
                source: dockSwipeSource,
                motion: motion,
                phase: phase,
                progress: progress,
                velocity: velocity
            )
        }
        guard !events.isEmpty else {
            return nil
        }
        self.init(cgEvents: events)
    }
}

private enum CGSEventType: Int64 {
    case gesture = 29
    case dockControl = 30
}

// MARK: - macOS 27 and later

/// - SeeAlso: IOHIDEventTypes.h and IOHIDEventFieldDefs.h in Apple's open source IOHIDFamily.
private enum DockSwipeHIDEvent {
    private typealias IOHIDEventCreate = @convention(c) (
        CFAllocator?, UInt32, UInt64, UInt32
    ) -> Unmanaged<CFTypeRef>?
    private typealias IOHIDEventSetIntegerValue = @convention(c) (CFTypeRef, UInt32, CFIndex) -> Void
    private typealias IOHIDEventSetDoubleValue = @convention(c) (CFTypeRef, UInt32, Double) -> Void
    private typealias IOHIDEventAppendEvent = @convention(c) (CFTypeRef, CFTypeRef, UInt32) -> Void
    private typealias SLEventSetIOHIDEvent = @convention(c) (CGEvent, CFTypeRef) -> Void

    private struct Functions {
        let create: IOHIDEventCreate
        let setInteger: IOHIDEventSetIntegerValue
        let setDouble: IOHIDEventSetDoubleValue
        let append: IOHIDEventAppendEvent
        let attach: SLEventSetIOHIDEvent
    }

    private static let functions: Functions? = {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let create = dlsym(iokit, "IOHIDEventCreate"),
              let setInteger = dlsym(iokit, "IOHIDEventSetIntegerValue"),
              let setDouble = dlsym(iokit, "IOHIDEventSetDoubleValue"),
              let append = dlsym(iokit, "IOHIDEventAppendEvent"),
              let attach = dlsym(skyLight, "SLEventSetIOHIDEvent")
        else {
            return nil
        }
        return Functions(
            create: unsafeBitCast(create, to: IOHIDEventCreate.self),
            setInteger: unsafeBitCast(setInteger, to: IOHIDEventSetIntegerValue.self),
            setDouble: unsafeBitCast(setDouble, to: IOHIDEventSetDoubleValue.self),
            append: unsafeBitCast(append, to: IOHIDEventAppendEvent.self),
            attach: unsafeBitCast(attach, to: SLEventSetIOHIDEvent.self)
        )
    }()

    private static let typeVelocity: UInt32 = 9
    private static let typeDockSwipe: UInt32 = 23
    private static let phaseShift: UInt32 = 24
    private static let gestureFlavorDockPrimary: CFIndex = 3

    private static func field(_ type: UInt32, _ index: UInt32) -> UInt32 {
        (type << 16) | index
    }

    static func cgEvents(
        source: CGEventSource?,
        motion: DockSwipeMotion,
        phase: CGSGesturePhase,
        progress: Double,
        velocity: Double
    ) -> [CGEvent] {
        guard let functions,
              let event = CGEvent(source: source),
              let hidEvent = functions.create(nil, typeDockSwipe, 0, UInt32(phase.rawValue) << phaseShift)?
                  .takeRetainedValue()
        else {
            return []
        }

        functions.setInteger(hidEvent, field(typeDockSwipe, 1), CFIndex(motion.rawValue))
        functions.setInteger(hidEvent, field(typeDockSwipe, 5), gestureFlavorDockPrimary)
        functions.setDouble(hidEvent, field(typeDockSwipe, 2), progress)

        if phase == .ended || phase == .cancelled,
           let velocityEvent = functions.create(nil, typeVelocity, 0, 0)?.takeRetainedValue() {
            functions.setDouble(velocityEvent, field(typeVelocity, 0), velocity)
            functions.setDouble(velocityEvent, field(typeVelocity, 1), velocity)
            functions.setDouble(velocityEvent, field(typeVelocity, 2), 0)
            functions.append(hidEvent, velocityEvent, 0)
        }

        event.setIntegerValueField(.eventType, value: CGSEventType.dockControl.rawValue)
        functions.attach(event, hidEvent)
        return [event]
    }
}

// MARK: - Before macOS 27

private enum DockSwipeFieldEvent {
    private static let magicValue: Int64 = 33_231

    static func cgEvents(
        source: CGEventSource?,
        motion: DockSwipeMotion,
        phase: CGSGesturePhase,
        progress: Double,
        velocity: Double
    ) -> [CGEvent] {
        guard let dockEvent = CGEvent(source: source),
              let gestureEvent = CGEvent(source: source)
        else {
            return []
        }

        dockEvent.setIntegerValueField(.eventType, value: CGSEventType.dockControl.rawValue)
        dockEvent.setIntegerValueField(.dockSwipeMagic, value: magicValue)
        dockEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.dockSwipe.rawValue))
        dockEvent.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        dockEvent.setIntegerValueField(.dockSwipePhase, value: Int64(phase.rawValue))
        dockEvent.setDoubleValueField(.dockSwipeProgress, value: progress)
        // The Dock also reads the progress as the bit pattern of a 32-bit float.
        dockEvent.setIntegerValueField(.dockSwipeProgressBits, value: Int64(Float32(progress).bitPattern))
        // The motion again, encoded as the bit pattern of a denormal float.
        let encodedMotion = Double(Float32(bitPattern: UInt32(motion.rawValue)))
        dockEvent.setDoubleValueField(.gestureScrollY, value: encodedMotion)
        dockEvent.setDoubleValueField(.dockSwipeEncodedMotion, value: encodedMotion)
        dockEvent.setIntegerValueField(.dockSwipeMotion, value: motion.rawValue)
        dockEvent.setIntegerValueField(.dockSwipeMotionAgain, value: motion.rawValue)
        dockEvent.setIntegerValueField(.dockSwipeInvertedFromDevice, value: 0)
        if phase == .ended || phase == .cancelled {
            dockEvent.setDoubleValueField(.gestureVelocityX, value: velocity)
            dockEvent.setDoubleValueField(.gestureVelocityY, value: velocity)
        }

        // The Dock only picks up the dock control event when it is followed by
        // a plain gesture event carrying the same marker.
        gestureEvent.setIntegerValueField(.eventType, value: CGSEventType.gesture.rawValue)
        gestureEvent.setIntegerValueField(.dockSwipeMagic, value: magicValue)

        return [dockEvent, gestureEvent]
    }
}

private extension CGEventField {
    static let dockSwipeMagic = Self(rawValue: 41)!
    static let eventType = Self(rawValue: 55)!
    static let dockSwipeMotion = Self(rawValue: 123)!
    static let dockSwipeProgress = Self(rawValue: 124)!
    static let gestureVelocityX = Self(rawValue: 129)!
    static let gestureVelocityY = Self(rawValue: 130)!
    static let dockSwipePhase = Self(rawValue: 134)!
    static let dockSwipeProgressBits = Self(rawValue: 135)!
    static let dockSwipeInvertedFromDevice = Self(rawValue: 136)!
    static let dockSwipeEncodedMotion = Self(rawValue: 139)!
    static let dockSwipeMotionAgain = Self(rawValue: 165)!
}
