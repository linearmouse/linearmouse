// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

func transformEvent(_ event: CGEvent) -> CGEvent? {
    var transformed: CGEvent? = event

    let transformers = ConfigurationState.shared.eventTransformers

    for transformer in transformers {
        if let transformedEvent = transformed {
            transformed = transformer.transform(transformedEvent)
        }
    }

    return transformed
}
