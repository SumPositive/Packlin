//
//  NumberFormatter.swift
//  PackList
//
//  Created by sumpo on 2025/09/23.
//

import Foundation

extension Formatter {
    static let decimalGrouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter
    }()
}

extension Int {
    var decimalGrouped: String {
        Formatter.decimalGrouping.string(from: NSNumber(value: self)) ?? String(self)
    }
}
