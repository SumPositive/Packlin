//
//  WeightTotalCapsule.swift
//  PackList
//
//  合計重量のカプセル。パック行の重量カプセルと同じ表記・色の決まりで表示する
//  （必要重量の表示設定・kg 表示設定に従い、全て充足なら青）
//

import SwiftUI

struct WeightTotalCapsule: View {
    let stockWeight: Int
    let needWeight: Int
    /// 全アイテムが充足しているか（青く表示する）
    let isSufficient: Bool

    @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = DEF_showNeedWeight
    @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = DEF_weightDisplayInKg

    private var labelText: String? {
        if showNeedWeight {
            guard 0 < stockWeight || 0 < needWeight else { return nil }
            return formattedWeightProgress(stock: stockWeight, need: needWeight)
        } else {
            guard 0 < stockWeight else { return nil }
            return formattedWeightWithUnit(stockWeight)
        }
    }

    private var state: QuantityCapsuleState { isSufficient ? .just : .over }

    var body: some View {
        if let labelText {
            Text(verbatim: labelText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(FONT_WEIGHT)
                .foregroundStyle(state.foregroundStyle)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(state.backgroundStyle(defaultColor: COLOR_ROW_GROUP))
                )
        }
    }

    private func formattedWeightWithUnit(_ weight: Int) -> String {
        // 1000g未満はgのまま、1000g以上は設定に応じてkgで丸める
        if weightDisplayInKg, 1000 <= weight {
            let kilogram = Double(weight) / 1000.0
            return "\(kilogram.oneDecimalGrouped)\(String(localized: "kg"))"
        }
        return "\(weight.decimalGrouped)\(String(localized: "g"))"
    }

    private func formattedWeightProgress(stock: Int, need: Int) -> String {
        if 0 < need, stock == need {
            return formattedWeightWithUnit(need)
        }
        if weightDisplayInKg, 1000 <= stock || 1000 <= need {
            let stockKilogram = Double(stock) / 1000.0
            let needKilogram = Double(need) / 1000.0
            return "\(stockKilogram.oneDecimalGrouped)/\(needKilogram.oneDecimalGrouped)\(String(localized: "kg"))"
        }
        return "\(stock.decimalGrouped)/\(need.decimalGrouped)\(String(localized: "g"))"
    }
}
