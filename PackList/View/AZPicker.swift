//
//  AZPicker.swift
//  PackList
//
//  体調メモ（Condition）の AZPicker から、プルダウン（ドロップダウン）系だけを移植したもの。
//  設定画面のラジオボタン式を、選択値がアクセント色で分かるプルダウンへ置き換えるために使う。
//

import SwiftUI
import UIKit

private extension DynamicTypeSize {
    /// UIKitの文字サイズ設定をSwiftUIのDynamicTypeSizeへ変換する
    init(uiContentSizeCategory category: UIContentSizeCategory) {
        switch category {
        case .extraSmall:                          self = .xSmall
        case .small:                               self = .small
        case .medium:                              self = .medium
        case .large:                               self = .large
        case .extraLarge:                          self = .xLarge
        case .extraExtraLarge:                     self = .xxLarge
        case .extraExtraExtraLarge:                self = .xxxLarge
        case .accessibilityMedium:                 self = .accessibility1
        case .accessibilityLarge:                  self = .accessibility2
        case .accessibilityExtraLarge:             self = .accessibility3
        case .accessibilityExtraExtraLarge:        self = .accessibility4
        case .accessibilityExtraExtraExtraLarge:   self = .accessibility5
        default:                                   self = .large
        }
    }
}

/// 幅不足時のテキスト処理
enum AZPickerTextFitMode {
    /// 文字サイズを維持して複数行にする
    case wrap
    /// 1行表示を優先し、収まらない時だけ縮小する
    case scale(minimumScaleFactor: CGFloat = 0.50)
}

/// `AZDropdownPicker` のボタン右端に出すインジケータ
enum AZDropdownIndicator {
    /// インジケータを表示しない
    case none
    /// 山型 chevron（展開で chevron.up、収納で chevron.down）
    case chevron
}

private extension View {
    /// Picker内テキストの幅不足時処理を適用する
    @ViewBuilder
    func azPickerTextFit(_ mode: AZPickerTextFitMode, alignment: TextAlignment) -> some View {
        switch mode {
        case .wrap:
            self
                .lineLimit(nil)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        case .scale(let minimumScaleFactor):
            self
                .lineLimit(1)
                .minimumScaleFactor(minimumScaleFactor)
                .allowsTightening(true)
                .multilineTextAlignment(alignment)
        }
    }
}

/// プルダウンの見た目をまとめて差し替えるためのスタイル
struct AZPickerStyle {
    /// 選択ボタン・候補枠の角丸
    var cornerRadius: CGFloat = 8
    /// 選択ボタンの背景色
    var panelBackground: Color = Color(.secondarySystemGroupedBackground)
    /// ドロップダウン候補の背景色
    var optionBackground: Color = Color(.systemBackground)
    /// 選択中の候補に重ねるアクセント背景の濃さ
    var selectedBackgroundOpacity: Double = 0.14
    /// 通常時の選択ボタン・候補の枠線の濃さ
    var borderOpacity: Double = 0.35
    /// 選択中または展開中の枠線の濃さ
    var selectedBorderOpacity: Double = 0.55
    /// 選択ボタンの影の濃さ
    var shadowOpacity: Double = 0
    /// 選択ボタンの影のぼかし
    var shadowRadius: CGFloat = 0
    /// 選択ボタンの影の縦方向位置
    var shadowY: CGFloat = 0
    /// ドロップダウン候補一覧パネルの影の濃さ
    var popoverShadowOpacity: Double = 0.10
    /// ドロップダウン候補一覧パネルの影のぼかし
    var popoverShadowRadius: CGFloat = 5
    /// ドロップダウン候補一覧パネルの影の縦方向位置
    var popoverShadowY: CGFloat = 2
    /// ドロップダウン各候補の枠内配置
    var dropdownOptionAlignment: Alignment = .leading
    /// ドロップダウン候補一覧内で候補枠を並べる横方向基準
    var dropdownOptionStackAlignment: HorizontalAlignment = .leading
    /// ドロップダウン各候補の複数行テキスト配置
    var dropdownOptionTextAlignment: TextAlignment = .leading
    /// ドロップダウン候補一覧パネル内側の余白
    var dropdownPopoverPadding: CGFloat = 10
    /// ドロップダウン各候補枠内の左右余白
    var dropdownOptionHorizontalPadding: CGFloat = 16
    /// ドロップダウン各候補枠内の上下余白
    var dropdownOptionVerticalPadding: CGFloat = 10
    /// ドロップダウン候補一覧だけに適用する文字サイズ範囲
    var dropdownPopoverDynamicTypeRange: ClosedRange<DynamicTypeSize> = DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5
    /// ドロップダウン選択中表示と候補一覧の幅不足時処理
    var dropdownTextFitMode: AZPickerTextFitMode = .wrap
    /// ラベル内で指定した色をそのまま使う
    var preservesLabelForegroundStyle: Bool = false
    /// 折りたたみ時に表示する選択値の文字色。
    /// 候補一覧の選択中項目と同じアクセント色にして、現在値が一目で分かるようにする
    var dropdownSelectedValueColor: Color = .accentColor
    /// 選択ボタン右端のインジケータ。デフォルトは非表示
    var dropdownIndicator: AZDropdownIndicator = .none

    /// 標準のフォーム向けスタイル
    static let form = AZPickerStyle()

    /// ドロップダウンの幅不足時処理だけを差し替える
    func dropdownTextFitMode(_ mode: AZPickerTextFitMode) -> AZPickerStyle {
        var copy = self
        copy.dropdownTextFitMode = mode
        return copy
    }
}

/// Dynamic Type対応のプルダウンPicker
struct AZDropdownPicker<Option: Hashable & Identifiable, Label: View>: View {
    @State private var buttonFrame: CGRect = .zero
    @State private var screenHeight: CGFloat = 0
    let options: [Option]
    @Binding var selection: Option
    @Binding var isExpanded: Bool
    var minWidth: CGFloat = 180
    var popoverDynamicTypeSize: DynamicTypeSize?
    /// 選択ボタンを親の横幅いっぱいに広げる
    var fillsWidth: Bool = false
    var style: AZPickerStyle = .form
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        collapsedButton
            .azDropdownPopover(
                isPresented: $isExpanded,
                anchorFrame: $buttonFrame,
                screenHeight: $screenHeight,
                backgroundColor: style.optionBackground,
                dynamicTypeSize: popoverDynamicTypeSize,
                dynamicTypeRange: style.dropdownPopoverDynamicTypeRange
            ) {
                expandedOptions
            }
            .zIndex(isExpanded ? 100 : 0)
    }

    private var popupMaxHeight: CGFloat {
        AZDropdownPopoverMetrics.maxHeight(
            anchorFrame: buttonFrame,
            screenHeight: screenHeight,
            margin: 20,
            minimumHeight: 120
        )
    }

    private var optionPanelWidth: CGFloat {
        max(minWidth, buttonFrame.width)
    }

    private var collapsedButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                selectedLabel
                indicatorView
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(
                minWidth: minWidth,
                maxWidth: fillsWidth ? .infinity : nil,
                alignment: .center
            )
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(style.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isExpanded ? Color.accentColor.opacity(style.selectedBorderOpacity) : Color.secondary.opacity(style.borderOpacity),
                        lineWidth: isExpanded ? 1.2 : 1
                    )
            )
            .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedLabel: some View {
        if style.preservesLabelForegroundStyle {
            label(selection)
                .font(.subheadline)
                .azPickerTextFit(style.dropdownTextFitMode, alignment: .center)
        } else {
            label(selection)
                .font(.subheadline)
                .foregroundStyle(style.dropdownSelectedValueColor)
                .azPickerTextFit(style.dropdownTextFitMode, alignment: .center)
        }
    }

    /// 選択ボタン右端のインジケータ。スタイル設定で非表示／chevron を切り替える
    @ViewBuilder
    private var indicatorView: some View {
        switch style.dropdownIndicator {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var expandedOptions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: style.dropdownOptionStackAlignment, spacing: 4) {
                    ForEach(options) { option in
                        optionButton(option)
                            // 選択中行へスクロールできるよう、各オプションに id を付与する
                            .id(option.id)
                    }
                }
                .frame(minWidth: optionPanelWidth, alignment: style.dropdownOptionAlignment)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: popupMaxHeight)
            // ポップオーバーが描画された直後に、選択中の行を中央に表示するようスクロールする
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(selection.id, anchor: .center)
                    }
                }
            }
        }
        .padding(style.dropdownPopoverPadding)
        // 内部パネルの塗りと枠線は描かず、popover背景と候補枠だけを使う
        .shadow(
            color: Color.black.opacity(style.popoverShadowOpacity),
            radius: style.popoverShadowRadius,
            x: 0,
            y: style.popoverShadowY
        )
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = selection == option
        return Button {
            selection = option
            withAnimation(.easeOut(duration: 0.12)) {
                isExpanded = false
            }
        } label: {
            AZDropdownOptionButton(
                isSelected: isSelected,
                minWidth: optionPanelWidth,
                style: style
            ) {
                label(option)
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
enum AZDropdownPopoverMetrics {
    /// 上下どちらの余白が広いかで、吹き出す向きを決める
    static func opensUpward(anchorFrame: CGRect, screenHeight: CGFloat) -> Bool {
        if anchorFrame == .zero {
            return true
        }
        let screenHeight = resolvedScreenHeight(screenHeight)
        let upperSpace = anchorFrame.minY
        let lowerSpace = screenHeight - anchorFrame.maxY
        return lowerSpace < upperSpace
    }

    static func maxHeight(
        anchorFrame: CGRect,
        screenHeight: CGFloat,
        margin: CGFloat = 20,
        minimumHeight: CGFloat = 120
    ) -> CGFloat {
        let screenHeight = resolvedScreenHeight(screenHeight)
        let upperSpace = max(minimumHeight, anchorFrame.minY - margin)
        let lowerSpace = max(minimumHeight, screenHeight - anchorFrame.maxY - margin)
        return opensUpward(anchorFrame: anchorFrame, screenHeight: screenHeight) ? upperSpace : lowerSpace
    }

    private static func resolvedScreenHeight(_ screenHeight: CGFloat) -> CGFloat {
        // 呼び出し側が画面高さを渡せない時は、MainActor上でUIKitから取得する
        if 0 < screenHeight {
            return screenHeight
        }
        return UIScreen.main.bounds.height
    }
}

struct AZDropdownPopoverModifier<PopoverContent: View>: ViewModifier {
    // 設定の文字サイズはアプリ共通の @AppStorage から読む（popover内は親環境を継承しないため）
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @Binding var isPresented: Bool
    @Binding var anchorFrame: CGRect
    @Binding var screenHeight: CGFloat
    var backgroundColor: Color
    var dynamicTypeSize: DynamicTypeSize?
    var dynamicTypeRange: ClosedRange<DynamicTypeSize>
    @ViewBuilder let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: AZDropdownPopoverMetrics.opensUpward(anchorFrame: anchorFrame, screenHeight: screenHeight) ? .bottom : .top
            ) {
                popoverContent()
                    // popover内は親環境を失いやすいため、標準で文字サイズを明示適用する
                    .dynamicTypeSize(resolvedDynamicTypeSize)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(backgroundColor)
                    // popoverの不透明背景を使い、内側パネルの角欠けを避ける
                    .padding(6)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            // 表示位置を測って、上下の広い側へ吹き出す
                            anchorFrame = proxy.frame(in: .global)
                            screenHeight = UIScreen.main.bounds.height
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            anchorFrame = newValue
                            // 実画面の高さで上下余白を比べ、狭い側へ縮む判定を避ける
                            screenHeight = UIScreen.main.bounds.height
                        }
                }
            }
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        let baseSize: DynamicTypeSize
        if let dynamicTypeSize {
            baseSize = dynamicTypeSize
        } else if fontScale.followsSystem {
            baseSize = DynamicTypeSize(uiContentSizeCategory: UIApplication.shared.preferredContentSizeCategory)
        } else {
            baseSize = fontScale.dynamicTypeSize
        }

        if baseSize < dynamicTypeRange.lowerBound {
            return dynamicTypeRange.lowerBound
        }
        if dynamicTypeRange.upperBound < baseSize {
            return dynamicTypeRange.upperBound
        }
        return baseSize
    }
}

extension View {
    func azDropdownPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        anchorFrame: Binding<CGRect>,
        screenHeight: Binding<CGFloat> = .constant(0),
        backgroundColor: Color = Color(.systemBackground),
        dynamicTypeSize: DynamicTypeSize? = nil,
        dynamicTypeRange: ClosedRange<DynamicTypeSize> = DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        modifier(
            AZDropdownPopoverModifier(
                isPresented: isPresented,
                anchorFrame: anchorFrame,
                screenHeight: screenHeight,
                backgroundColor: backgroundColor,
                dynamicTypeSize: dynamicTypeSize,
                dynamicTypeRange: dynamicTypeRange,
                popoverContent: content
            )
        )
    }
}

/// ドロップダウン候補一覧の1行
struct AZDropdownOptionButton<Label: View>: View {
    let isSelected: Bool
    var minWidth: CGFloat
    var lineLimit: Int? = nil
    var style: AZPickerStyle = .form
    @ViewBuilder let label: () -> Label

    var body: some View {
        optionLabel
            .padding(.horizontal, style.dropdownOptionHorizontalPadding)
            .padding(.vertical, style.dropdownOptionVerticalPadding)
            .frame(minWidth: minWidth, maxWidth: .infinity, alignment: style.dropdownOptionAlignment)
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(style.selectedBackgroundOpacity) : style.optionBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(style.selectedBorderOpacity) : Color.secondary.opacity(style.borderOpacity),
                        lineWidth: isSelected ? 1.2 : 1
                    )
            )
    }

    @ViewBuilder
    private var optionLabel: some View {
        if style.preservesLabelForegroundStyle {
            label()
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .azPickerTextFit(style.dropdownTextFitMode, alignment: style.dropdownOptionTextAlignment)
                .lineLimit(lineLimit)
        } else {
            label()
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .azPickerTextFit(style.dropdownTextFitMode, alignment: style.dropdownOptionTextAlignment)
                .lineLimit(lineLimit)
        }
    }
}

/// コントロール行を「見出し込み1行」「見出し＋操作部2段」の順に選ぶ
struct AZAdaptiveControlRow<Title: View, Control: View>: View {
    @ViewBuilder let title: () -> Title
    @ViewBuilder let control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                title()
                Spacer(minLength: 8)
                control()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                title()
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
