//
//  SettingRadioGroup.swift
//  PackList
//
//  Dynamic Type 対応のオリジナルラジオボタン UI 群。
//  設定画面の `.segmented` ピッカーを置き換える目的で、Calclin と同じ実装パターンを利用する。
//

import SwiftUI

/// Dynamic Type で文字が欠けないラジオボタン型の選択 UI（純粋な選択肢グループ）
struct SettingRadioGroup<Option: Hashable & Identifiable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var minOptionWidth: CGFloat = 96
    var maxOptionWidth: CGFloat = 240
    var horizontalPadding: CGFloat = 10
    var optionSpacing: CGFloat = 6
    var groupPadding: CGFloat = 6
    var wrapsOptions: Bool = true
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        optionLayout
            .padding(groupPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 2, x: 0, y: 1)
            .frame(maxWidth: wrapsOptions ? .infinity : nil, alignment: .trailing)
    }

    @ViewBuilder
    private var optionLayout: some View {
        if wrapsOptions {
            SettingFlowLayout(spacing: optionSpacing, rowSpacing: optionSpacing) {
                optionButtons
            }
        } else {
            HStack(spacing: optionSpacing) {
                optionButtons
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var optionButtons: some View {
        ForEach(options) { option in
            optionButton(option)
        }
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = selection == option
        return Button {
            selection = option
        } label: {
            ZStack {
                label(option)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // ラジオボタン内の文字は「大」までで頭打ち（特大時の欠落を防ぐ）
                    .cappedAtLargeFontSize()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(minWidth: minOptionWidth,
                   maxWidth: maxOptionWidth,
                   alignment: .center)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.systemBackground).opacity(0.96))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.66) : Color.secondary.opacity(0.10),
                                  lineWidth: isSelected ? 1.25 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.02 : 0.055),
                    radius: isSelected ? 0.4 : 1.2,
                    x: 0,
                    y: isSelected ? 0 : 0.8)
            .overlay(alignment: .top) {
                if isSelected {
                    // 選択中は薄い内側線で押し込まれた印象を弱めに出す
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// ラジオ行を「見出し込み1行」「2段で選択肢1行」「選択肢折り返し」の順に選ぶ
struct AdaptiveRadioRow<Option: Hashable & Identifiable, Title: View, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var minOptionWidth: CGFloat = 96
    var maxOptionWidth: CGFloat = 240
    var horizontalPadding: CGFloat = 10
    var optionSpacing: CGFloat = 6
    var groupPadding: CGFloat = 6
    @ViewBuilder let title: () -> Title
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                title()
                Spacer(minLength: 8)
                radioGroup(wrapsOptions: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                title()
                radioGroup(wrapsOptions: false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 3) {
                title()
                radioGroup(wrapsOptions: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func radioGroup(wrapsOptions: Bool) -> some View {
        SettingRadioGroup(options: options,
                          selection: $selection,
                          minOptionWidth: minOptionWidth,
                          maxOptionWidth: maxOptionWidth,
                          horizontalPadding: horizontalPadding,
                          optionSpacing: optionSpacing,
                          groupPadding: groupPadding,
                          wrapsOptions: wrapsOptions) { option in
            label(option)
        }
    }
}

/// 選択肢を自然幅で並べ、入らない時だけ次の行へ送る Flow Layout
struct SettingFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? subviews.reduce(CGFloat.zero) { partial, subview in
            partial + subview.sizeThatFits(.unspecified).width + spacing
        }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextX = x == 0 ? size.width : x + spacing + size.width
            if availableWidth < nextX && 0 < x {
                usedWidth = max(usedWidth, x)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x = x == 0 ? size.width : x + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
        usedWidth = max(usedWidth, x)

        return CGSize(width: min(usedWidth, availableWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var rows: [[(index: Int, size: CGSize)]] = []
        var currentRow: [(index: Int, size: CGSize)] = []
        var currentWidth: CGFloat = 0
        var y = bounds.minY

        for index in subviews.indices {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = currentRow.isEmpty ? size.width : currentWidth + spacing + size.width
            if bounds.width < nextWidth && currentRow.isEmpty == false {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
            }
            currentRow.append((index, size))
            currentWidth = currentRow.count == 1 ? size.width : currentWidth + spacing + size.width
        }
        if currentRow.isEmpty == false {
            rows.append(currentRow)
        }

        for row in rows {
            let rowWidth = row.reduce(CGFloat.zero) { partial, item in
                partial + item.size.width
            } + spacing * CGFloat(max(row.count - 1, 0))
            let rowHeight = row.reduce(CGFloat.zero) { partial, item in
                max(partial, item.size.height)
            }
            var x = bounds.maxX - rowWidth
            for item in row {
                let subview = subviews[item.index]
                subview.place(at: CGPoint(x: x, y: y),
                              proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
