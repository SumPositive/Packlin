//
//  NumericKeypadView.swift
//  PackList
//
//  クレメモ（CreditMemo/Components/NumericKeypadView.swift）の金額テンキーを移植したもの。
//  画面下部に固定する簡易電卓付きテンキー。Packlin の数量（個重量・在庫数・必要数）は
//  0以上の整数なので、通貨・符号切り替え・丸め方法の選択は省き、割り算の端数は四捨五入する
//

import SwiftUI
import UIKit

/// 簡易電卓で使う四則演算子
enum NumericCalculatorOperator: CaseIterable, Identifiable {
    case divide
    case multiply
    case subtract
    case add

    var id: Self { self }

    var symbol: String {
        switch self {
        case .divide:   "÷"
        case .multiply: "×"
        case .subtract: "−"
        case .add:      "+"
        }
    }
}

/// 計算できなかった理由。View 側でエラー文言に対応づける
enum NumericCalculatorError: Error, Equatable {
    /// 0 で割ろうとした
    case divideByZero
    /// 結果が上限を超えた
    case tooLarge
    /// 結果がマイナスになった（数量は0以上）
    case negative

    var localizedKey: LocalizedStringKey {
        switch self {
        case .divideByZero: "calculator.error.divideByZero"
        case .tooLarge:     "calculator.error.tooLarge"
        case .negative:     "calculator.error.negative"
        }
    }
}

/// テンキーの計算規則。状態を持たないので単体で検証できる
enum NumericCalculatorEngine {
    /// 二項演算を行い、0〜maxValue に収まるか確かめる（途中の値は丸めない）
    static func calculate(_ left: Decimal,
                          _ operation: NumericCalculatorOperator,
                          _ right: Decimal,
                          maxValue: Decimal) -> Result<Decimal, NumericCalculatorError> {
        let result: Decimal
        switch operation {
        case .divide:
            guard right != 0 else { return .failure(.divideByZero) }
            result = left / right
        case .multiply:
            result = left * right
        case .subtract:
            result = left - right
        case .add:
            result = left + right
        }
        guard 0 <= result else { return .failure(.negative) }
        guard result <= maxValue else { return .failure(.tooLarge) }
        return .success(result)
    }

    /// 整数へ四捨五入する
    static func rounded(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return result
    }
}

// MARK: - テンキーオーバーレイ

/// システムシートを使わず画面下部へ固定する00キー付きテンキー（四則演算付き）
/// - 現在値をプレースホルダーとして表示（グレー）し、未入力で決定するとそのまま登録する
struct NumericKeypadOverlay: View {
    let title: LocalizedStringKey
    let unit: LocalizedStringKey
    /// 現在値（プレースホルダー兼デフォルト値）
    let placeholder: Int
    let maxValue: Int
    let onCancel: () -> Void
    /// 確定時コールバック（未入力時は placeholder をそのまま渡す）
    let onCommit: (Int) -> Void

    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @State private var digits: String = ""
    @State private var accumulator: Decimal?
    @State private var pendingOperator: NumericCalculatorOperator?
    @State private var calculationResult: Decimal?
    @State private var calculationError: NumericCalculatorError?

    private var isEmpty: Bool { digits.isEmpty }
    private var isCompact: Bool { UIScreen.main.bounds.height <= 700 }
    private var sheetSpacing: CGFloat { isCompact ? 10 : 14 }
    private var displayFontSize: CGFloat { isCompact ? 44 : 52 }
    private var maxDecimal: Decimal { Decimal(maxValue) }

    private var enteredValue: Decimal? {
        guard !isEmpty, let number = Decimal(string: digits) else { return nil }
        return number
    }

    private var activeValue: Decimal {
        if pendingOperator != nil, let calculationResult { return calculationResult }
        if let enteredValue { return enteredValue }
        if let calculationResult { return calculationResult }
        if let accumulator { return accumulator }
        return Decimal(placeholder)
    }

    /// 登録する値（整数へ四捨五入し、0〜maxValue に収める）
    private var committedValue: Int {
        let value = NSDecimalNumber(decimal: NumericCalculatorEngine.rounded(activeValue)).intValue
        return min(max(value, 0), maxValue)
    }

    /// 割り算などで端数が出ているか（式の結果に端数を見せ、上段は四捨五入した値を出す）
    private var hasFraction: Bool {
        calculationResult != nil && NumericCalculatorEngine.rounded(activeValue) != activeValue
    }

    private var displayValueText: String {
        // 乗除算の右辺を入力中は、その数値をそのまま大きく見せる
        if calculationResult == nil, !digits.isEmpty, pendingOperator != nil {
            return numberText(enteredValue ?? 0)
        }
        return numberText(Decimal(committedValue))
    }

    private var displayColor: Color {
        let isPristine = digits.isEmpty && accumulator == nil && calculationResult == nil
        return isPristine ? Color(.tertiaryLabel) : Color(.label)
    }

    private var expressionText: String? {
        guard let accumulator, let pendingOperator else { return nil }
        let left = numberText(accumulator, fractionDigits: hasFractionPart(accumulator) ? 1 : 0)
        guard let right = enteredValue else { return "\(left) \(pendingOperator.symbol)" }
        let resultSuffix: String = {
            guard calculationResult != nil else { return "" }
            return " = \(numberText(activeValue, fractionDigits: hasFraction ? 1 : 0))"
        }()
        return "\(left) \(pendingOperator.symbol) \(numberText(right))\(resultSuffix)"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 背面全体でタップを受け、編集中フォームの誤操作を防ぐ。
                // 背面のタップで閉じる（入力中の値は確定しない）
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { onCancel() }

                VStack(spacing: sheetSpacing) {
                    header

                    valueDisplayRow

                    if let expressionText {
                        Text(expressionText)
                            .font(.title3.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, -sheetSpacing / 2)
                    }

                    if let calculationError {
                        Text(calculationError.localizedKey)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(alignment: .top, spacing: isCompact ? 8 : 10) {
                        NumericKeypad(compact: isCompact) { key in
                            handleKey(key)
                        }
                        CalculatorOperatorKeypad(compact: isCompact,
                                                 selectedOperator: pendingOperator,
                                                 onSelect: selectOperator)
                    }
                    .padding(.horizontal, isCompact ? 16 : 20)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        commitCalculation()
                    } label: {
                        Text("done.2")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)
                    .padding(.bottom, isCompact ? 2 : 6)
                }
                .padding(.top, 8)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
                .background(Color(uiColor: .systemGroupedBackground))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24,
                                                  topTrailingRadius: 24,
                                                  style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 12, y: -2)
            }
        }
        .ignoresSafeArea()
        // テンキーは「大」までで頭打ちにして、キーが画面からはみ出さないようにする
        .cappedAtLargeFontSize()
        // 表示切替や入力更新でオーバーレイを動かさない
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(title)
                .font(.headline)
            Spacer()
            // タイトルを中央に保つため、左の閉じるボタンと同じ幅を空ける
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }

    /// 四捨五入後の値を単位付きで大きく表示する
    private var valueDisplayRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(displayValueText)
                .font(.system(size: displayFontSize, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.38)
                .allowsTightening(true)
            Text(unit)
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func handleKey(_ key: NumericKeypadKey) {
        calculationError = nil
        switch key {
        case .digit(let d): appendDigits(String(d))
        case .doubleZero:   appendDigits("00")
        case .delete:       deleteLastInput()
        }
    }

    private func appendDigits(_ suffix: String) {
        let next: String
        if digits.isEmpty || digits == "0" {
            next = suffix.hasPrefix("0") ? "0" : suffix
        } else {
            next = digits + suffix
        }
        guard let number = Decimal(string: next), 0 <= number else { return }
        guard next.count <= String(maxValue).count, number <= maxDecimal else { return }
        digits = next
        updateCalculationPreview()
    }

    private func deleteLastInput() {
        if !digits.isEmpty {
            digits.removeLast()
            updateCalculationPreview()
            return
        }
        guard pendingOperator != nil, let left = accumulator else { return }

        // 右辺を消し終えた次の⌫で演算子を外し、左辺を再編集できる形へ戻す
        // 左辺は計算途中の未丸めの値なので、四捨五入した整数で入力欄へ戻す
        pendingOperator = nil
        calculationResult = nil
        accumulator = nil
        let settled = NSDecimalNumber(decimal: NumericCalculatorEngine.rounded(left)).intValue
        digits = String(min(max(settled, 0), maxValue))
    }

    private func selectOperator(_ newOperator: NumericCalculatorOperator) {
        calculationError = nil
        if let currentOperator = pendingOperator,
           let left = accumulator,
           let right = enteredValue {
            guard let result = calculate(left, currentOperator, right) else { return }
            accumulator = result
            calculationResult = result
        } else if accumulator == nil {
            accumulator = activeValue
        }
        pendingOperator = newOperator
        digits = ""
    }

    private func updateCalculationPreview() {
        guard let left = accumulator,
              let pendingOperator,
              let right = enteredValue else {
            calculationResult = nil
            return
        }
        calculationResult = calculate(left, pendingOperator, right)
    }

    private func commitCalculation() {
        if let left = accumulator,
           let pendingOperator,
           let right = enteredValue {
            guard let result = calculate(left, pendingOperator, right) else { return }
            calculationResult = result
        }
        onCommit(committedValue)
    }

    /// 計算規則は NumericCalculatorEngine に持たせ、ここでは結果を画面状態へ反映する
    private func calculate(_ left: Decimal,
                           _ operation: NumericCalculatorOperator,
                           _ right: Decimal) -> Decimal? {
        switch NumericCalculatorEngine.calculate(left, operation, right, maxValue: maxDecimal) {
        case .success(let result):
            calculationError = nil
            return result
        case .failure(let error):
            calculationError = error
            return nil
        }
    }

    private func numberText(_ value: Decimal, fractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private func hasFractionPart(_ value: Decimal) -> Bool {
        NumericCalculatorEngine.rounded(value) != value
    }
}

// MARK: - テンキーキー種別

enum NumericKeypadKey {
    case digit(Int)
    case doubleZero
    case delete
}

// MARK: - テンキービュー

/// 3×3 + 0・00・⌫ 行のテンキー
struct NumericKeypad: View {
    let compact: Bool
    let onKey: (NumericKeypadKey) -> Void

    private let rows = [[7, 8, 9], [4, 5, 6], [1, 2, 3]]

    init(compact: Bool = false, onKey: @escaping (NumericKeypadKey) -> Void) {
        self.compact = compact
        self.onKey = onKey
    }

    private var spacing: CGFloat { compact ? 8 : 10 }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { digit in
                        KeypadDigitButton(label: "\(digit)", compact: compact) { onKey(.digit(digit)) }
                    }
                }
            }
            // 最終行: 0 / 00 / ⌫
            HStack(spacing: spacing) {
                KeypadDigitButton(label: "0", compact: compact) { onKey(.digit(0)) }
                KeypadDigitButton(label: "00", compact: compact) { onKey(.doubleZero) }
                KeypadDeleteButton(compact: compact) { onKey(.delete) }
            }
        }
    }
}

/// 数字キー右端へ固定する四則演算子列
private struct CalculatorOperatorKeypad: View {
    let compact: Bool
    let selectedOperator: NumericCalculatorOperator?
    let onSelect: (NumericCalculatorOperator) -> Void

    private var spacing: CGFloat { compact ? 8 : 10 }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(NumericCalculatorOperator.allCases) { operation in
                CalculatorOperatorButton(operation: operation,
                                         compact: compact,
                                         isSelected: selectedOperator == operation) {
                    onSelect(operation)
                }
            }
        }
    }
}

// MARK: - ボタンパーツ

/// 数字キーと同じ高さで表示する演算子ボタン
private struct CalculatorOperatorButton: View {
    let operation: NumericCalculatorOperator
    let compact: Bool
    let isSelected: Bool
    let action: () -> Void

    private var size: CGFloat { compact ? 52 : 56 }

    var body: some View {
        Button(action: action) {
            Text(operation.symbol)
                .font(compact ? .title2.weight(.semibold) : .title.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: size, height: size)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(operation.symbol))
    }
}

private struct KeypadDigitButton: View {
    let label: String
    let compact: Bool
    let action: () -> Void

    private var minHeight: CGFloat { compact ? 52 : 56 }
    private var font: Font { compact ? .title2.weight(.medium) : .title.weight(.medium) }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct KeypadDeleteButton: View {
    let compact: Bool
    let action: () -> Void

    private var minHeight: CGFloat { compact ? 52 : 56 }
    private var font: Font { compact ? .title3 : .title2 }

    var body: some View {
        Button(action: action) {
            Image(systemName: "delete.left")
                .font(font)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
