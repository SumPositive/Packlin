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

    static let oneDecimalGrouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        // Kg表示では小数第一位までを四捨五入して表示したいので、桁数と丸めモードを固定する
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()
}

extension Int {
    var decimalGrouped: String {
        Formatter.decimalGrouping.string(from: NSNumber(value: self)) ?? String(self)
    }
}

extension Double {
    var oneDecimalGrouped: String {
        Formatter.oneDecimalGrouping.string(from: NSNumber(value: self)) ?? String(format: "%.1f", self)
    }
}
