//
//  ObservationToken.swift
//
//
//  Created by Jiahao Lu on 2022/6/14.
//

public final class ObservationToken {
    private let cancellationClosure: () -> Void

    init(cancellationClosure: @escaping () -> Void) {
        self.cancellationClosure = cancellationClosure
    }

    deinit {
        cancellationClosure()
    }

    private var lifetimeAssociation: LifetimeAssociation? = nil

    @discardableResult
    public func tieToLifetime(of weaklyHeldObject: AnyObject) -> Self {
        lifetimeAssociation = LifetimeAssociation(of: self, with: weaklyHeldObject, deinitHandler: { [weak self] in
            self?.cancellationClosure()
        })

        return self
    }

    public func removeLifetime() {
        lifetimeAssociation?.cancel()
    }
}
