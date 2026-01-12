// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Comparable {
    func clamp(_ x: Self, _ y: Self) -> Self {
        let low = min(x, y)
        let high = max(x, y)

        return max(low, min(self, high))
    }
}
