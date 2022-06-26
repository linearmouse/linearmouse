// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(range.lowerBound, self), range.upperBound)
    }
}

extension BinaryInteger {
    func normalized(fromLowerBound: Self = 0, fromUpperBound: Self = 1, toLowerBound: Self = 0,
                    toUpperBound: Self = 1) -> Self {
        let k = (toUpperBound - toLowerBound) / (fromUpperBound - fromLowerBound)
        return (self - fromLowerBound) * k + toLowerBound
    }

    func normalized(from: ClosedRange<Self> = 0 ... 1, to: ClosedRange<Self> = 0 ... 1) -> Self {
        normalized(fromLowerBound: from.lowerBound, fromUpperBound: from.upperBound,
                   toLowerBound: to.lowerBound, toUpperBound: to.upperBound)
    }
}

extension BinaryFloatingPoint {
    func normalized(fromLowerBound: Self = 0, fromUpperBound: Self = 1, toLowerBound: Self = 0,
                    toUpperBound: Self = 1) -> Self {
        let k = (toUpperBound - toLowerBound) / (fromUpperBound - fromLowerBound)
        return (self - fromLowerBound) * k + toLowerBound
    }

    func normalized(from: ClosedRange<Self> = 0 ... 1, to: ClosedRange<Self> = 0 ... 1) -> Self {
        normalized(fromLowerBound: from.lowerBound, fromUpperBound: from.upperBound,
                   toLowerBound: to.lowerBound, toUpperBound: to.upperBound)
    }
}
