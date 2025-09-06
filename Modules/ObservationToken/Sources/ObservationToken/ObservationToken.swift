// MIT License
// Copyright (c) 2021-2025 LinearMouse

public final class ObservationToken {
    private let cancellationClosure: () -> Void
    private var cancelled = false

    public init(cancellationClosure: @escaping () -> Void) {
        self.cancellationClosure = cancellationClosure
    }

    deinit {
        cancel()
    }

    private var lifetimeAssociation: LifetimeAssociation?

    @discardableResult
    public func tieToLifetime(of weaklyHeldObject: AnyObject) -> Self {
        lifetimeAssociation = LifetimeAssociation(of: self, with: weaklyHeldObject) { [weak self] in
            self?.cancellationClosure()
        }

        return self
    }

    public func removeLifetime() {
        lifetimeAssociation?.cancel()
    }

    public func cancel() {
        guard !cancelled else {
            return
        }

        cancelled = true
        cancellationClosure()
    }
}
