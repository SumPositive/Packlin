//
//  AZFlowLayout.swift
//  PackList
//
//  クレメモ（CreditMemo/Components/AZPicker.swift）の AZFlowLayout を移植したもの。
//  行末の余白に後方の収まる要素を繰り上げて詰める（packToFill）ことができる
//

import SwiftUI

/// 選択肢を自然幅で並べ、入らない時だけ次の行へ送る
struct AZFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat
    /// 各行の横方向の寄せ。既定は従来どおり右寄せ（.trailing）。
    /// 左寄せ（.leading）・中央寄せ（.center）にしたい呼び出し側だけ指定する。
    var alignment: HorizontalAlignment = .trailing
    /// true のとき、行末の余白に後方の“収まる”subview を繰り上げて詰める（bin-packing）。
    /// 既定は false（並び順どおりの単純な折り返し）。
    var packToFill: Bool = false
    /// true のとき、各行の余りを subview の幅へ均等に配って行幅いっぱいに広げる。
    /// 間隔は spacing のまま固定で、カプセル自体が広がる。
    /// 幅を広げる方式なので最終行も（要素が1つでも）そのまま均等にできる。
    /// 行分けの規則は変えないので、packToFill との併用もできる
    var justified: Bool = false

    /// 各 subview の実サイズ。行分けと配置で共有する。
    private func sizes(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    /// subview を行（index の配列）に振り分ける。availableWidth を超えない範囲で、
    /// packToFill のときは行末の余白に収まる後方要素を繰り上げて詰める。
    /// 単体テストから行分けを確かめられるよう、private にしない
    func makeRows(sizes: [CGSize], availableWidth: CGFloat) -> [[Int]] {
        let n = sizes.count
        guard n > 0 else { return [] }
        // 幅が未確定（0 や無限大）のときは全体を1行にして測定に委ねる
        guard availableWidth.isFinite, availableWidth > 0 else { return [Array(0..<n)] }

        var placed = [Bool](repeating: false, count: n)
        var rows: [[Int]] = []

        while let start = placed.firstIndex(of: false) {
            placed[start] = true
            var row = [start]
            var used = sizes[start].width

            while true {
                let free = availableWidth - used - spacing
                if free <= 0 { break }
                // packToFill: 収まる“最初の”後方要素を繰り上げ。
                // 通常: 並び順で次の要素が収まるときだけ足す（見つからなければ改行）。
                let range = (start + 1)..<n
                let pick: Int?
                if packToFill {
                    pick = range.first { !placed[$0] && sizes[$0].width <= free }
                } else {
                    if let next = range.first(where: { !placed[$0] }) {
                        pick = sizes[next].width <= free ? next : nil
                    } else {
                        pick = nil
                    }
                }
                guard let idx = pick else { break }
                placed[idx] = true
                row.append(idx)
                used += spacing + sizes[idx].width
            }
            rows.append(row)
        }
        return rows
    }

    /// 配置するときに行分けに使う幅。sizeThatFits と同じ幅（提案された幅）で分ける
    /// sizeThatFits は一番長い行の幅に縮んだ大きさを返すので、bounds.width だけで分け直すと
    /// 本来入るはずの後方の要素が次の行へ落ちてしまう
    static func placementWidth(boundsWidth: CGFloat, proposalWidth: CGFloat?) -> CGFloat {
        let proposed = proposalWidth.flatMap { $0.isFinite ? $0 : nil } ?? boundsWidth
        return max(boundsWidth, proposed)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let s = sizes(subviews)
        let availableWidth = proposal.width ?? s.reduce(CGFloat.zero) { $0 + $1.width + spacing }
        let rows = makeRows(sizes: s, availableWidth: availableWidth)

        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowWidth = row.reduce(CGFloat.zero) { $0 + s[$1].width } + spacing * CGFloat(max(row.count - 1, 0))
            let rowHeight = row.reduce(CGFloat.zero) { max($0, s[$1].height) }
            maxRowWidth = max(maxRowWidth, rowWidth)
            totalHeight += rowHeight
            if i < rows.count - 1 { totalHeight += rowSpacing }
        }
        let width = proposal.width ?? maxRowWidth
        return CGSize(width: min(maxRowWidth, width), height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let s = sizes(subviews)
        // 行分けは sizeThatFits と同じ幅で行う（理由は placementWidth を参照）
        let rows = makeRows(sizes: s, availableWidth: Self.placementWidth(boundsWidth: bounds.width,
                                                                          proposalWidth: proposal.width))
        var y = bounds.minY

        for row in rows {
            let rowWidth = row.reduce(CGFloat.zero) { $0 + s[$1].width } + spacing * CGFloat(max(row.count - 1, 0))
            let rowHeight = row.reduce(CGFloat.zero) { max($0, s[$1].height) }

            // 均等割りは行幅いっぱいに広げる。間隔は spacing のまま固定にして、
            // 余りは各 subview の幅へ均等に配る（カプセル自体が広がる）。
            // 幅を広げる方式なので、要素が1つだけの最終行も均等にできる
            let canJustify = justified && !row.isEmpty
            let extraWidth = canJustify
                ? max(bounds.width - rowWidth, 0) / CGFloat(row.count)
                : 0

            // 左寄せは行左端から、中央寄せは余白を左右に二等分、
            // 右寄せ（既定）は行右端から詰める。均等割りの行は左端から広げる
            var x: CGFloat
            if canJustify {
                x = bounds.minX
            } else {
                switch alignment {
                case .leading: x = bounds.minX
                case .center:  x = bounds.minX + max(bounds.width - rowWidth, 0) / 2
                default:       x = bounds.maxX - rowWidth
                }
            }
            for idx in row {
                // 自然幅が帯幅を超える subview は帯幅で頭打ちにして提案する。
                // これで内部（例：ラベル＋金額の HStack）に幅制限が伝わり、
                // 優先度の低い要素だけが省略され、右端の要素は残せる。
                // 均等割りのときは余りを足した幅を提案してカプセルを広げる
                let placeWidth = min(s[idx].width + extraWidth, bounds.width)
                subviews[idx].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: placeWidth, height: s[idx].height)
                )
                x += placeWidth + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
