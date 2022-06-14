//
//  Dictionary.swift
//  
//
//  Created by Jiahao Lu on 2022/6/14.
//

import Foundation

extension Dictionary where Key == UUID {
    mutating func insert(_ value: Value) -> UUID {
        let id = UUID()
        self[id] = value
        return id
    }
}
