//
//  QuantityCapsuleState.swift
//  PackList
//

import SwiftUI

enum QuantityCapsuleState {
    case under
    case just
    case over

    var foregroundStyle: Color {
        switch self {
        case .just:
            return .blue
        case .under, .over:
            return COLOR_WEIGHT
        }
    }

    func backgroundStyle(defaultColor: Color) -> Color {
        switch self {
        case .just:
            return Color.blue.opacity(0.14)
        case .under, .over:
            return defaultColor
        }
    }
}
