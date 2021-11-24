//
//  Transformer.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

func getTransformers(appDefaults: AppDefaults, mouseDetector: MouseDetector) -> [EventTransformer] {
    let orientNormalizer = OrientNormalizer()

    let transformers: [(Bool, () -> EventTransformer)] = [
        (true,                                  { orientNormalizer }),
        (appDefaults.reverseScrollingOn,        { ReverseScrolling(mouseDetector: mouseDetector) }),
        (appDefaults.linearScrollingOn,         { LinearScrolling(mouseDetector: mouseDetector,
                                                                  scrollLines: appDefaults.scrollLines) }),
        (appDefaults.universalBackForwardOn,    { UniversalBackForward() }),
        (true,                                  { ModifierActions(mouseDetector: mouseDetector,
                                                                  commandAction: appDefaults.modifiersCommandAction,
                                                                  shiftAction: appDefaults.modifiersShiftAction,
                                                                  alternateAction: appDefaults.modifiersAlternateAction,
                                                                  controlAction: appDefaults.modifiersControlAction) }),
        (true,                                  { orientNormalizer }),
    ]

    return transformers.filter { $0.0 }.map { $0.1() }
}

func transformEvent(appDefaults: AppDefaults, mouseDetector: MouseDetector, event: CGEvent) -> CGEvent? {
    var transformed: CGEvent? = event
    let transformers = getTransformers(appDefaults: appDefaults, mouseDetector: mouseDetector)
    for transformer in transformers {
        if let transformedEvent = transformed {
            transformed = transformer.transform(transformedEvent)
        }
    }
    return transformed
}
