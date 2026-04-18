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

    private var committedValue: Int {
        guard !isEmpty, let v = Int(digits) else { return placeholder }
        return min(v, maxValue)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // ── 入力表示エリア ──
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Spacer()
                    Text(isEmpty ? "\(placeholder)" : digits)
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isEmpty ? Color(.tertiaryLabel) : Color(.label))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: digits)
                    Text(unit)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // ── テンキー ──
                NumericKeypad { key in handleKey(key) }

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
                .padding(.bottom, 12)
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
        .presentationDetents([.fraction(0.65)])
        .presentationDragIndicator(.visible)
    }

    private func handleKey(_ key: NumericKeypadKey) {
        switch key {
        case .digit(let d):
            // 空または "0" の状態では新しい数字で置き換え（先頭ゼロ防止）
            if digits.isEmpty || digits == "0" {
                digits = String(d)
                return
            }
            let next = digits + String(d)
            // 最大桁数チェック
            guard next.count <= String(maxValue).count else { return }
            // 最大値チェック
            guard let v = Int(next), v <= maxValue else { return }
            digits = next
        case .delete:
            if !digits.isEmpty { digits.removeLast() }
        }
    }
}

// MARK: - テンキーキー種別

enum NumericKeypadKey {
    case digit(Int)
    case delete
}

// MARK: - テンキービュー

/// 3×3 + 0(広め)・⌫ 行のテンキー
struct NumericKeypad: View {
    let onKey: (NumericKeypadKey) -> Void

    private let rows = [[7, 8, 9], [4, 5, 6], [1, 2, 3]]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        KeypadDigitButton(digit: digit) { onKey(.digit(digit)) }
                    }
                }
            }
            // 最終行: 0（2列分）+ ⌫（1列分）
            GeometryReader { geo in
                let spacing: CGFloat = 10
                let buttonWidth = (geo.size.width - spacing * 2) / 3
                HStack(spacing: spacing) {
                    KeypadDigitButton(digit: 0) { onKey(.digit(0)) }
                        .frame(width: buttonWidth * 2 + spacing)
                    KeypadDeleteButton { onKey(.delete) }
                        .frame(width: buttonWidth)
                }
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - ボタンパーツ

private struct KeypadDigitButton: View {
    let digit: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(digit)")
                .font(.title.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct KeypadDeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "delete.left")
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
