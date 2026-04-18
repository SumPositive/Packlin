//
//  NumericKeypadView.swift
//  PackList
//

import SwiftUI

/// 専用テンキー入力シート
/// - 現在値をプレースホルダーとして表示（グレー）
/// - 入力した値をそのまま登録（上書き）
struct NumericKeypadSheet: View {
    let title: LocalizedStringKey
    let unit: LocalizedStringKey
    /// 現在値（プレースホルダー兼デフォルト値）
    let placeholder: Int
    let maxValue: Int
    /// 確定時コールバック（未入力時は placeholder をそのまま渡す）
    let onCommit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits: String = ""

    private var isEmpty: Bool { digits.isEmpty }
    private var isSmallScreen: Bool { UIScreen.main.bounds.height <= 700 }
    private var sheetSpacing: CGFloat { isSmallScreen ? 14 : 20 }
    private var displayFontSize: CGFloat { isSmallScreen ? 48 : 56 }
    private var topPadding: CGFloat { isSmallScreen ? 4 : 8 }
    private var bottomPadding: CGFloat { isSmallScreen ? 6 : 12 }

    private var committedValue: Int {
        guard !isEmpty, let v = Int(digits) else { return placeholder }
        return min(v, maxValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: sheetSpacing) {
                // ── 入力表示エリア ──
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Spacer()
                    Text(isEmpty ? "\(placeholder)" : digits)
                        .font(.system(size: displayFontSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isEmpty ? Color(.tertiaryLabel) : Color(.label))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: digits)
                    Text(unit)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, topPadding)

                // ── テンキー ──
                NumericKeypad(compact: isSmallScreen) { key in handleKey(key) }

                // ── 決定ボタン ──
                Button {
                    onCommit(committedValue)
                    dismiss()
                } label: {
                    Text("決定")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, bottomPadding)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .presentationDetents(isSmallScreen ? [.fraction(0.7), .large] : [.fraction(0.65), .large])
        .presentationDragIndicator(.visible)
    }

    private func handleKey(_ key: NumericKeypadKey) {
        switch key {
        case .digit(let d):
            appendDigits(String(d))
        case .doubleZero:
            appendDigits("00")
        case .delete:
            if !digits.isEmpty { digits.removeLast() }
        }
    }

    private func appendDigits(_ suffix: String) {
        // 空または "0" の状態では新しい数字列で置き換え（先頭ゼロ防止）
        let next: String
        if digits.isEmpty || digits == "0" {
            next = suffix
        } else {
            next = digits + suffix
        }

        guard let value = Int(next) else { return }
        // 最大桁数チェック
        guard next.count <= String(maxValue).count else { return }
        // 最大値チェック
        guard value <= maxValue else { return }
        digits = String(value)
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
    private var horizontalPadding: CGFloat { compact ? 16 : 20 }

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
        .padding(.horizontal, horizontalPadding)
    }
}

// MARK: - ボタンパーツ

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
