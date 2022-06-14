//
//  Comparable+Extensions.swift
//  
//
//  Created by Jiahao Lu on 2022/6/14.
//

extension Comparable {
    internal func clamp(_ x: Self, _ y: Self) -> Self {
        let low = min(x, y)
        let high = max(x, y)

        return max(low, min(self, high))
    }
}
