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

func transformEvent(appDefaults: AppDefaults, mouseDetector: MouseDetector, event: CGEvent) -> CGEvent? {
    let orientNormalizer = OrientNormalizer()
    let transformers: [EventTransformer] = [
        orientNormalizer,
        ReverseScrolling(appDefaults: appDefaults, mouseDetector: mouseDetector),
        LinearScrolling(appDefaults: appDefaults, mouseDetector: mouseDetector),
        UniversalBackForward(appDefaults: appDefaults),
        ModifierActions(appDefaults: appDefaults, mouseDetector: mouseDetector),
        orientNormalizer,
    ]
    var transformed: CGEvent? = event
    for transformer in transformers {
        if let transformedEvent = transformed {
            transformed = transformer.transform(transformedEvent)
        }
    }
    return transformed
}
