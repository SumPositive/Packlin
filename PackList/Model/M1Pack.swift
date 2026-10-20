//
//  M1Pack.swift
//  PackList
//　　　 データ量的には3次元配列で十分だが、逐次保存など堅牢にするためにDBにする
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M1Pack {
    typealias ID = String
    @Attribute(.unique) var id: ID
    var order: Int

    var name: String
    var memo: String

    var createdAt: Date

    /// 公開済みパックのサーバー側ID。`nil` なら未公開、値があれば「公開中」。
    /// パックセルに「公開中」バッジを出す判定や、公開取消時のローカル状態同期に使う。
    /// SwiftData のオプショナル追加なので既存DBは自動で軽量マイグレーションされる。
    var publishedId: String?

    /// 分類方式（PackClassifyMode の rawValue）。`nil` はグループ式。
    /// 既存DBのパックは nil のまま読み込まれるのでグループ式になり、新規パックだけ作成時にタグ式を入れる。
    var classifyModeRaw: String?

    var classifyMode: PackClassifyMode {
        get { classifyModeRaw.flatMap(PackClassifyMode.init(rawValue:)) ?? .group }
        set { classifyModeRaw = newValue.rawValue }
    }

    /// タグ式で追加したアイテムの入れ先グループのID（「タグ式グループ」）
    /// グループ式へ戻したときに、タグ式で足したアイテムが1つのグループにまとまって見えるようにする
    var tagModeGroupID: String?

    @Relationship(deleteRule: .cascade) var child: [M2Group] = []

    var stock: Int { child.reduce(0) { $0 + $1.stock } }
    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.stockWeight } }
    var needWeight: Int { child.reduce(0) { $0 + $1.needWeight } }

    /// タグ式グループを除く通常グループの件数
    var regularGroupCount: Int {
        child.filter { $0.id != tagModeGroupID }.count
    }

    /// 通常グループは30件、タグ式グループは別枠で扱う
    var canAddRegularGroup: Bool { regularGroupCount < APP_MAX_PART_ROWS }

    /// アイテム数はグループごとではなくパック全体で制限する
    func canAddItems(_ count: Int = 1) -> Bool {
        // 既存の超過データでも、件数を増やさない操作は許可する
        guard 0 <= count else { return false }
        return count == 0 || itemCount <= APP_MAX_PACK_ITEMS - count
    }

    /// 既存の超過データも含めた実際のアイテム件数
    var itemCount: Int { child.reduce(0) { $0 + $1.child.count } }

    /// パック内のアイテムに付いているタグの一覧（重複なし・名前順）
    /// タグは独立したデータを持たず、アイテムで使われているものを集めて一覧にする
    var allTags: [String] {
        let tags = Set(child.flatMap { $0.child.flatMap(\.tags) })
        return tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// タグごとの付いているアイテム数
    var tagItemCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for group in child {
            for item in group.child {
                for tag in item.tags {
                    counts[tag, default: 0] += 1
                }
            }
        }
        return counts
    }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         createdAt: Date = Date(),
         order: Int = 0) {
        self.id = id
        self.name = name
        self.memo = memo
        self.createdAt = createdAt
        self.order = order
    }
    
    /// タグ式でアイテムを追加するときの入れ先グループ（「タグ式グループ」）
    /// 初回に末尾へ作り、以後は同じグループへ入れる。名前を変えても ID で辿るので同じグループのまま。
    /// 削除されていたら作り直す
    func groupForNewItem() -> M2Group {
        if let tagModeGroupID,
           let group = child.first(where: { $0.id == tagModeGroupID }) {
            return group
        }
        let group = M2Group(name: String(localized: "tag.mode.group.name"),
                            order: nextGroupOrder(),
                            parent: self)
        modelContext?.insert(group)
        tagModeGroupID = group.id
        return group
    }

    /// タグの名前を変える。このパックで同じタグが付いたアイテムすべてに反映する
    /// 変更後の名前が既にあるときは1つのタグにまとまる
    func renameTag(_ oldTag: String, to newTag: String) {
        for group in child {
            for item in group.child where item.tags.contains(oldTag) {
                item.tags = M3Item.sanitizedTags(item.tags.map { $0 == oldTag ? newTag : $0 })
            }
        }
    }

    /// タグを、このパックのすべてのアイテムから外す
    func removeTag(_ tag: String) {
        for group in child {
            for item in group.child where item.tags.contains(tag) {
                item.tags.removeAll { $0 == tag }
            }
        }
    }

    /// 指定順のタグの並び：指定順の並びで先に出てくるアイテムのタグから並べる
    /// 1つのアイテムに新しいタグが複数あるときは、付いているアイテム数の多い順（同数はアイテムでの並びどおり）
    /// アイテムを並べ替えると、タグの並びも付いてくる
    var tagsInManualOrder: [String] {
        let counts = tagItemCounts
        var seen = Set<String>()
        var tags: [String] = []
        for item in itemsInManualOrder {
            let newTags = item.tags.filter { !seen.contains($0) }
            guard !newTags.isEmpty else { continue }
            // 同数のタグはアイテムでの並びのまま残す
            let ordered = newTags.enumerated().sorted { lhs, rhs in
                let lhsCount = counts[lhs.element] ?? 0
                let rhsCount = counts[rhs.element] ?? 0
                if lhsCount != rhsCount {
                    return rhsCount < lhsCount
                }
                return lhs.offset < rhs.offset
            }.map(\.element)
            for tag in ordered where seen.insert(tag).inserted {
                tags.append(tag)
            }
        }
        return tags
    }

    /// 指定順（グループの順 → グループ内のアイテムの順）の全アイテム
    var itemsInManualOrder: [M3Item] {
        child.sorted { $0.order < $1.order }
            .flatMap { group in group.child.sorted { $0.order < $1.order } }
    }

    /// 指定順でアイテムをドラッグ移動する（アイテム縦覧のタグ式）
    /// - Parameters:
    ///   - visible: 縦覧に見えているアイテム（絞り込み後、指定順）。source / destination はこの並びでの位置
    /// - 絞り込み中は見えている行だけを並べ替えたことになるので、「見えている直前の行の直後」へ入れる
    ///   （先頭へ動かしたときは「見えている先頭の行の直前」）。見えない行どうしの順番は変えない
    /// - 移動したアイテムは、入れた位置の直前のアイテムのグループへ移る（先頭なら直後のアイテムのグループ）
    ///   グループ式に戻したときも、見た目の並びがそのまま保たれる
    func moveItemsInManualOrder(visible: [M3Item], from source: IndexSet, to destination: Int) {
        let moving = source.sorted().compactMap { visible.indices.contains($0) ? visible[$0] : nil }
        guard !moving.isEmpty else { return }
        let movingIDs = Set(moving.map(\.id))
        let remainingVisible = visible.filter { !movingIDs.contains($0.id) }
        // 動かすアイテムを除いた見えている行での、落とした位置
        let dropIndex = destination - source.filter { $0 < destination }.count

        // 指定順の全アイテムから、動かすアイテムを除いた並び
        var ordered = itemsInManualOrder.filter { !movingIDs.contains($0.id) }
        let insertIndex: Int
        if 0 < dropIndex, remainingVisible.indices.contains(dropIndex - 1) {
            let previous = remainingVisible[dropIndex - 1]
            guard let index = ordered.firstIndex(where: { $0.id == previous.id }) else { return }
            insertIndex = index + 1
        } else if let next = remainingVisible.first {
            guard let index = ordered.firstIndex(where: { $0.id == next.id }) else { return }
            insertIndex = index
        } else {
            return
        }
        guard let targetGroup = (0 < insertIndex ? ordered[insertIndex - 1].parent : nil)
                ?? (insertIndex < ordered.count ? ordered[insertIndex].parent : nil) else { return }

        ordered.insert(contentsOf: moving, at: insertIndex)
        for item in moving where item.parent?.id != targetGroup.id {
            item.parent = targetGroup
        }
        // 入れた先のグループの順序を、指定順の並びどおりに振り直す
        normalizeSparseOrders(ordered.filter { $0.parent?.id == targetGroup.id })
    }

    /// グループ式からタグ式へ変えたとき、グループ名をタグにして配下のアイテムに付ける
    /// - 「タグ式グループ」は元々タグ式で足したアイテムの入れ物なので対象外
    /// - 名前が空のグループは付けるタグが無いので対象外
    /// - 既に同じタグがあれば付け直さない（何度切り替えても重複しない）。上限や文字数は sanitizedTags に従う
    func tagItemsWithGroupNames() {
        for group in child where group.id != tagModeGroupID {
            // 改行を含む名前もタグとして1行にそろえる
            let tag = group.name
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty else { continue }
            for item in group.child {
                let tags = M3Item.sanitizedTags(item.tags + [tag])
                if tags != item.tags {
                    item.tags = tags
                }
            }
        }
    }

    /// 子グループの order を連番に整理する
    /// - Note: 表示順は List 側で order を基準にソートするため、ここでは child 配列を書き換えない。
    ///         order だけを唯一の真実源として扱い、配列の順番は放置する。
    func normalizeGroupOrder() {
        // SwiftData の child 配列は順序が保証されないため、order と id で安定ソートしてから並べ替える
        let sorted = child.sorted { ll, rr in
            if ll.order != rr.order {
                return ll.order < rr.order
            }
            return ll.id < rr.id
        }
        // スパース間隔で再採番するが、child の並びはそのまま残す
        normalizeSparseOrders(sorted)
    }

    /// 次のグループの order 値を取得する
    func nextGroupOrder() -> Int {
        let ordered = child.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            // order だけを整えて child 配列には触れない
            normalizeSparseOrders(ordered)
        }
    }

    /// パック全体の order を連番に整理する
    static func normalizePackOrder(_ packs: [M1Pack]) {
        let sorted = packs.sorted { $0.order < $1.order }
        // 配列の並び順は呼び出し側で適切に反映する前提。ここでは order のみ更新する。
        normalizeSparseOrders(sorted)
    }

    /// 次のパックの order 値を取得する
    static func nextPackOrder(_ packs: [M1Pack]) -> Int {
        let ordered = packs.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            normalizeSparseOrders(ordered)
        }
    }
    
    /// 現在の Pack を削除し、残った Pack の order を再正規化する
    ///
    /// 削除の流れ:
    ///   1. 配下の Group をすべて削除（各 Group の delete() は配下 Item の削除と
    ///      親 Pack の order 整理を内部で行うが、ここでは Pack 自体が消えるので
    ///      最後の order 整理は無駄になる。気にしないでよい範囲のオーバーヘッド。）
    ///   2. 自身を削除
    ///   3. 残った全 Pack を再フェッチして order を 0, 1000, 2000... に振り直す
    ///
    /// === Fix 4 関連: イテレーション安全性 ===
    /// `self.child` を直接 for-in すると、ループ中の `group.delete()` で SwiftData が
    /// `self.child` 内部キャッシュを更新する可能性があり、未定義動作になり得る。
    /// そのため Array(...) で明示的にスナップショット化してからループする。
    func delete() {
        guard let mc = modelContext else {return}

        // === Step 1: 配下の Group をすべて削除 ===
        // Array(...) でスナップショット化することで、ループ中の SwiftData 内部更新
        // から切り離してイテレーションする（詳細は M2Group.delete() のコメント参照）。
        let groups = Array(self.child)
        for group in groups {
            // 各 Group の delete() は内部で配下 Item の削除と親 Pack の
            // normalizeGroupOrder() を呼ぶが、親 Pack がもうすぐ消えるので
            // この normalize は実質的に無効になる（ペナルティは小さい）。
            group.delete()
        }

        // === Step 2: 自身を削除 ===
        mc.delete(self)

        // === Step 3: 全 Pack の order を正規化 ===
        // 削除によって order に隙間ができる（例: 0, 1000, 2000 → 0, 2000）。
        // 隙間は機能的には問題ないが、長期運用で order が大きな値になり過ぎるのを
        // 防ぐため、ここで 0, 1000, 2000... に振り直す。
        // fetch 失敗時は order 整理を諦める（次回起動時の操作で再正規化される）。
        let descriptor = FetchDescriptor<M1Pack>()
        if let packs = try? mc.fetch(descriptor) {
            M1Pack.normalizePackOrder(packs)
        }
    }
    
    /// 現在の Pack を複製し、現在の行のすぐ下に追加する
    ///
    /// 複製仕様:
    ///   - name / memo はコピー
    ///   - createdAt は **現在時刻**を採用（元の createdAt を引き継ぐとシート表示からの
    ///     複製でユーザーが混乱しやすいため）
    ///   - 新しい Pack の order は **`sparseOrderForInsertion` で「自分と次の Pack の中間」を計算**
    ///     （Fix 6 で改善。旧版の `self.order + 1` は隣接 Pack の order と衝突する可能性があった）
    ///   - 配下の Group / Item をすべて新規生成して複製
    ///   - アイテムの check=false / stock=0 にリセット（need と weight は維持）
    ///     → 「テンプレート的な使い方」を想定し、進捗系はリセット
    ///
    /// === Fix 6: order 一時衝突の対策 ===
    /// 旧版は `order: self.order + 1` で挿入していたが、これには以下の問題があった：
    ///   - 隣接する Pack の order が既に `self.order + 1` だった場合、衝突が発生
    ///   - 衝突状態で `normalizePackOrder` を呼ぶと、`id` のタイブレークで並びが
    ///     予測しづらくなる（複製した Pack が既存の隣 Pack の下に行くか上に行くか不定）
    ///   - 連続して同じ Pack を複製すると、毎回 `self.order + 1` が同じ値を取り
    ///     順序が乱れる
    ///
    /// 新版は `sparseOrderForInsertion` を使う：
    ///   - 自分と次の Pack の order の中間値を計算（gap があれば衝突しない）
    ///   - gap が不足している場合はクロージャ内で全 Pack を正規化してから再計算
    ///   - 末尾複製なら `self.order + ORDER_SPARSE` を返す
    /// これにより複製直後の段階で衝突が起こらない order が保証される。
    func duplicate() {
        guard let mc = modelContext else {return}

        // === Step 1: 全 Pack を取得して並び順を確定する ===
        // 自分の次の Pack を特定するために、まず order でソートされた配列を作る。
        // fetch 失敗時は安全側に倒して self.order + ORDER_SPARSE を使う。
        let sortedPacks: [M1Pack]
        if let fetched = try? mc.fetch(FetchDescriptor<M1Pack>()) {
            sortedPacks = fetched.sorted { $0.order < $1.order }
        } else {
            sortedPacks = []
        }

        // === Step 2: 自分のインデックスを特定する ===
        // SwiftData @Model はクラスなので `===` で同一性比較も可能だが、
        // id 比較の方が明示的でリレーションシップキャッシュの揺らぎに強い。
        let selfIndex = sortedPacks.firstIndex(where: { $0.id == self.id })

        // === Step 3: 自分の直後に挿入する order を sparseOrderForInsertion で算出 ===
        // - 自分が見つからない場合は末尾扱い（fetch 失敗時のフォールバック）
        // - 見つかれば selfIndex + 1 の位置に挿入する order を計算
        // - 隣接する order と衝突しない値が必ず返る（必要なら正規化が走る）
        let insertionIndex = (selfIndex ?? (sortedPacks.count - 1)) + 1
        let newOrder = sparseOrderForInsertion(
            items: sortedPacks,
            index: insertionIndex
        ) {
            // gap 不足時の正規化。0, 1000, 2000... に振り直してから order を計算し直す
            normalizeSparseOrders(sortedPacks)
        }

        // === Step 4: 新しい Pack を作成 ===
        // createdAt を現在時刻にする理由:
        //   - 元と同一値だと UI 上で「どちらが新しい複製か」判別困難
        //   - normalizePackOrder のタイブレークでも createdAt は使うので、
        //     新しい時刻にしておけば挙動が予測しやすい
        let newPack = M1Pack(name: self.name,
                             memo: self.memo,
                             createdAt: Date(),
                             order: newOrder)
        newPack.classifyModeRaw = self.classifyModeRaw
        mc.insert(newPack)

        // === Step 2: 配下の Group / Item を再帰的に複製 ===
        // SwiftData の @Relationship は context.insert() の度に親の child 配列が
        // 暗黙的に変動することがある。そのためイテレーション対象の self.child を
        // Array(...) でスナップショット化してから for-in する。
        // （詳細は M2Group.duplicate() のコメント参照）
        let groups = Array(self.child)
        for group in groups {
            // Group を新規作成して新 Pack に紐付ける
            let newGroup = M2Group(name: group.name,
                                   memo: group.memo,
                                   order: group.order,
                                   parent: newPack)
            mc.insert(newGroup)
            // タグ式グループは複製先でも同じ役割を引き継ぐ（次の追加で2つ目ができないように）
            if group.id == self.tagModeGroupID {
                newPack.tagModeGroupID = newGroup.id
            }

            // Group 配下の Item も同様に Array(...) で固定してから複製
            let items = Array(group.child)
            for item in items {
                let newItem = M3Item(name: item.name,
                                     memo: item.memo,
                                     check: false,        // 進捗は引き継がない
                                     stock: 0,            // 在庫もリセット
                                     need: item.need,     // 必要数は引き継ぐ
                                     weight: item.weight, // 個重量は引き継ぐ
                                     tags: item.tags,     // タグも引き継ぐ
                                     order: item.order,
                                     parent: newGroup)
                mc.insert(newItem)
            }
        }

        // === 最終 Step: 全 Pack の order を正規化（ハウスキーピング） ===
        // Fix 6 適用後は sparseOrderForInsertion で衝突しない order を得ているため、
        // このタイミングでの normalize は「必須」ではなく「長期運用での order 数値が
        // 大きくなりすぎないようにする」ためのハウスキーピング目的。
        // 副作用なく安全に呼べるので、従来通り実行しておく。
        // 全件再フェッチして 0, 1000, 2000... に振り直す。
        let descriptor = FetchDescriptor<M1Pack>()
        if let packs = try? mc.fetch(descriptor) {
            M1Pack.normalizePackOrder(packs)
        }
    }
    
}

protocol SparseOrderable: AnyObject {
    var order: Int { get set }
}

extension M1Pack: SparseOrderable {}
extension M2Group: SparseOrderable {}
extension M3Item: SparseOrderable {}

/// スパース間隔で順序を振り直す。呼び出し側が順序付き配列を用意する前提。
func normalizeSparseOrders<T: SparseOrderable>(_ items: [T]) {
    for (index, element) in items.enumerated() {
        // index * ORDER_SPARSE_COUNT でベースラインを維持しつつ、挿入余地を確保する
        element.order = index * ORDER_SPARSE
    }
}

/// 指定した位置へ挿入する際のスパース order を算出する
func sparseOrderForInsertion<T: SparseOrderable>(
    items: [T],
    index: Int,
    normalize: () -> Void
) -> Int {
    let clampedIndex = max(0, min(index, items.count))
    return sparseOrderValue(
        previous: { 0 < clampedIndex ? items[clampedIndex - 1].order : nil },
        next: { clampedIndex < items.count ? items[clampedIndex].order : nil },
        normalize: normalize
    )
}

private func sparseOrderValue(
    previous: () -> Int?,
    next: () -> Int?,
    normalize: () -> Void
) -> Int {
    if let prev = previous(), let nextValue = next() {
        let gap = nextValue - prev
        // gap が 1 以下なら余白が無いため正規化して再計算する
        if gap <= 1 {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
        // gap を二等分した位置を採用することで、両側の順序を壊さずに挿入する
        return prev + gap / 2
    } else if let prev = previous() {
        // 末尾への追加。オーバーフロー時は正規化して再計算する
        let (result, overflow) = prev.addingReportingOverflow(ORDER_SPARSE)
        if overflow {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
        return result
    } else if let nextValue = next() {
        // 先頭への追加。アンダーフロー時は正規化して再計算する
        let (result, overflow) = nextValue.subtractingReportingOverflow(ORDER_SPARSE)
        if overflow {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
        return result
    } else {
        // 要素が存在しない場合は 0 を基点にする
        return 0
    }
}

/// ドラッグ移動などで連続した範囲に新しい order を割り振る
func assignSparseOrders<T: SparseOrderable>(
    nodes: [T],
    range: ClosedRange<Int>,
    normalize: () -> Void
) {
    guard !nodes.isEmpty else { return }
    let lower = max(range.lowerBound, 0)
    let upper = min(range.upperBound, nodes.count - 1)
    guard lower <= upper else { return }

    let count = upper - lower + 1
    let previousOrder = 0 < lower ? nodes[lower - 1].order : nil
    let nextOrder = upper + 1 < nodes.count ? nodes[upper + 1].order : nil

    if let previous = previousOrder, let next = nextOrder {
        let gap = next - previous
        // gap が count 以下の場合は均等割りできず、正規化を要求する
        if gap <= count {
            normalize()
            return
        }
        // gap を (count + 1) で割ると等間隔の差分が得られる。
        let step = max(1, gap / (count + 1))
        var current = previous
        for offset in 0..<count {
            current += step
            nodes[lower + offset].order = current
        }
    } else if let previous = previousOrder {
        var current = previous
        for index in lower...upper {
            let (next, overflow) = current.addingReportingOverflow(ORDER_SPARSE)
            if overflow {
                normalize()
                return
            }
            current = next
            nodes[index].order = current
        }
    } else if let next = nextOrder {
        var current = next
        for index in stride(from: upper, through: lower, by: -1) {
            let (prev, overflow) = current.subtractingReportingOverflow(ORDER_SPARSE)
            if overflow {
                normalize()
                return
            }
            current = prev
            nodes[index].order = current
        }
    } else {
        var current = 0
        for index in lower...upper {
            nodes[index].order = current
            current += ORDER_SPARSE
        }
    }
}
