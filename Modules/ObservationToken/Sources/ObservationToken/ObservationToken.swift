// MIT License
// Copyright (c) 2021-2023 LinearMouse

public final class ObservationToken {
    private let cancellationClosure: () -> Void

    public init(cancellationClosure: @escaping () -> Void) {
        self.cancellationClosure = cancellationClosure
    }

    deinit {
        cancellationClosure()
    }

    private var lifetimeAssociation: LifetimeAssociation?

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
