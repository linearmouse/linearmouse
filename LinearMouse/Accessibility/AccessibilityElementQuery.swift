// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
import CoreGraphics

enum AccessibilityQueryResult<Value> {
    case success(Value)
    case failure(AXError)
}

protocol AccessibilityElementQuerying {
    func systemWideElement(at point: CGPoint) -> AccessibilityQueryResult<AXUIElement?>
    func element(at point: CGPoint, in rootElement: AXUIElement) -> AccessibilityQueryResult<AXUIElement?>
    func requiredStringValue(of attribute: CFString, on element: AXUIElement) -> AccessibilityQueryResult<String?>
    func optionalStringValue(of attribute: CFString, on element: AXUIElement) -> AccessibilityQueryResult<String?>
    func optionalElementValue(of attribute: CFString, on element: AXUIElement) -> AccessibilityQueryResult<AXUIElement?>
    func optionalElementArrayValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<[AXUIElement]?>
    func optionalAttributeValue(of attribute: CFString, on element: AXUIElement) -> AccessibilityQueryResult<CFTypeRef?>
    func optionalPointValue(of attribute: CFString, on element: AXUIElement) -> AccessibilityQueryResult<CGPoint?>
    func optionalSizeValue(of attribute: CFString, on element: AXUIElement) -> AccessibilityQueryResult<CGSize?>
    func optionalFrameValue(of element: AXUIElement) -> AccessibilityQueryResult<CGRect?>
    func optionalActionNames(of element: AXUIElement) -> AccessibilityQueryResult<[String]>
}

struct AccessibilityElementQuery: AccessibilityElementQuerying {
    func systemWideElement(at point: CGPoint) -> AccessibilityQueryResult<AXUIElement?> {
        element(at: point, in: AXUIElementCreateSystemWide())
    }

    func element(at point: CGPoint, in rootElement: AXUIElement) -> AccessibilityQueryResult<AXUIElement?> {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(rootElement, Float(point.x), Float(point.y), &hitElement)
        guard error == .success else {
            return .failure(error)
        }

        return .success(hitElement)
    }

    func requiredStringValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<String?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return .failure(error)
        }

        return .success(value as? String)
    }

    func optionalStringValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<String?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            return .success(value as? String)
        case .noValue, .attributeUnsupported:
            return .success(nil)
        default:
            return .failure(error)
        }
    }

    func optionalElementValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<AXUIElement?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            guard let value else {
                return .success(nil)
            }

            return .success(value as! AXUIElement)
        case .noValue, .attributeUnsupported:
            return .success(nil)
        default:
            return .failure(error)
        }
    }

    func optionalElementArrayValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<[AXUIElement]?> {
        switch optionalAttributeValue(of: attribute, on: element) {
        case let .success(value):
            guard let value else {
                return .success(nil)
            }

            return .success(value as? [AXUIElement])
        case let .failure(error):
            return .failure(error)
        }
    }

    func optionalAttributeValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<CFTypeRef?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            return .success(value)
        case .noValue, .attributeUnsupported:
            return .success(nil)
        default:
            return .failure(error)
        }
    }

    func optionalPointValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<CGPoint?> {
        switch optionalAttributeValue(of: attribute, on: element) {
        case let .success(value):
            guard let value,
                  CFGetTypeID(value) == AXValueGetTypeID() else {
                return .success(nil)
            }

            let axValue = value as! AXValue
            var point = CGPoint.zero
            guard AXValueGetType(axValue) == .cgPoint,
                  AXValueGetValue(axValue, .cgPoint, &point) else {
                return .success(nil)
            }

            return .success(point)
        case let .failure(error):
            return .failure(error)
        }
    }

    func optionalSizeValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<CGSize?> {
        switch optionalAttributeValue(of: attribute, on: element) {
        case let .success(value):
            guard let value,
                  CFGetTypeID(value) == AXValueGetTypeID() else {
                return .success(nil)
            }

            let axValue = value as! AXValue
            var size = CGSize.zero
            guard AXValueGetType(axValue) == .cgSize,
                  AXValueGetValue(axValue, .cgSize, &size) else {
                return .success(nil)
            }

            return .success(size)
        case let .failure(error):
            return .failure(error)
        }
    }

    func optionalFrameValue(of element: AXUIElement) -> AccessibilityQueryResult<CGRect?> {
        let position: CGPoint?
        switch optionalPointValue(of: kAXPositionAttribute as CFString, on: element) {
        case let .success(value):
            position = value
        case let .failure(error):
            return .failure(error)
        }

        let size: CGSize?
        switch optionalSizeValue(of: kAXSizeAttribute as CFString, on: element) {
        case let .success(value):
            size = value
        case let .failure(error):
            return .failure(error)
        }

        guard let position, let size else {
            return .success(nil)
        }

        return .success(CGRect(origin: position, size: size))
    }

    func optionalActionNames(of element: AXUIElement) -> AccessibilityQueryResult<[String]> {
        var actions: CFArray?
        let error = AXUIElementCopyActionNames(element, &actions)
        switch error {
        case .success:
            return .success(actions as? [String] ?? [])
        case .noValue, .actionUnsupported, .attributeUnsupported:
            return .success([])
        default:
            return .failure(error)
        }
    }
}

extension AXError {
    var linearMouseDescription: String {
        switch self {
        case .success:
            "success"
        case .failure:
            "failure"
        case .illegalArgument:
            "illegalArgument"
        case .invalidUIElement:
            "invalidUIElement"
        case .invalidUIElementObserver:
            "invalidUIElementObserver"
        case .cannotComplete:
            "cannotComplete"
        case .attributeUnsupported:
            "attributeUnsupported"
        case .actionUnsupported:
            "actionUnsupported"
        case .notificationUnsupported:
            "notificationUnsupported"
        case .notImplemented:
            "notImplemented"
        case .notificationAlreadyRegistered:
            "notificationAlreadyRegistered"
        case .notificationNotRegistered:
            "notificationNotRegistered"
        case .apiDisabled:
            "apiDisabled"
        case .noValue:
            "noValue"
        case .parameterizedAttributeUnsupported:
            "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:
            "notEnoughPrecision"
        @unknown default:
            "unknown(\(rawValue))"
        }
    }
}
