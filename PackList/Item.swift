//
//  Item.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
