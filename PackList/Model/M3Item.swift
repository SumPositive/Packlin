//
//  M3Item.swift
//  PackList
//　　　 データ量的には3次元配列で十分だが、逐次保存など堅牢にするためにDBにする
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M3Item {
    typealias ID = String
    @Attribute(.unique) var id: ID
    var order: Int // 表示順

    var name: String
    var memo: String
    var check: Bool // チェック
    var stock: Int  // 在庫数
    var need: Int   // 必要数
    var weight: Int // 重量(g)

    @Relationship(inverse: \M2Group.child) var parent: M2Group?

    var lack: Int { max(need - stock, 0) }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         check: Bool = false,
         stock: Int = 0,
         need: Int = 1,     // 初期1にした
         weight: Int = 0,
         order: Int = 0,
         parent: M2Group? = nil) {
        self.id = id
        self.name = name
        self.memo = memo
        self.check = check
        self.stock = stock
        self.need = need
        self.weight = weight
        self.order = order
        self.parent = parent
    }


    /// アイテム削除
    func delete() {
        guard let mc = modelContext else {return}

        // 削除後に順序調整できるよう、親グループの識別子を退避する
        let parentGroupID = self.parent?.persistentModelID

        mc.delete(self)

        // 再フェッチしてchild配列から除かれた状態の親グループでorderを整理する
        if let parentGroupID {
            let descriptor = FetchDescriptor<M2Group>(
                predicate: #Predicate { element in
                    element.persistentModelID == parentGroupID
                }
            )
            if let reloadedParent = try? mc.fetch(descriptor).first {
                reloadedParent.normalizeItemOrder()
            }
        }
    }

    /// 現在の Item を複製し、現在の行のすぐ下に追加する
    ///
    /// 複製仕様:
    ///   - 新しいアイテムは元と同じ name / memo / need / weight を持つ
    ///   - check=false / stock=0 にリセット（進捗系はリセット、テンプレ的に使い回す想定）
    ///   - 新しい Item の order は **`sparseOrderForInsertion` で「自分と次の Item の中間」を計算**
    ///     （Fix 6 で改善。旧版の `self.order + 1` は隣接 Item の order と衝突する可能性があった）
    ///
    /// === Fix 6: order 一時衝突の対策 ===
    /// 旧版は `order: self.order + 1` で挿入していたが、隣接 Item の order と
    /// 衝突する可能性があり、`normalizeItemOrder` 後の並びが id タイブレークで
    /// 不定になる事故があった。詳細は M1Pack.duplicate() のコメント参照。
    /// 新版は `sparseOrderForInsertion` で「自分と次の Item の中間」を計算する。
    func duplicate() {
        guard let mc = modelContext else {return}
        guard let parent = self.parent else { return }

        // === Step 1: 親グループ配下の Item を order でソートして並び順を確定 ===
        // parent.child は SwiftData リレーションシップで順序が保証されないため、
        // 自分の次のアイテムを特定するためにここで明示ソートしておく。
        let sortedItems = parent.child.sorted { $0.order < $1.order }

        // === Step 2: 自分のインデックスを特定する ===
        // id 比較で確実に自分の位置を取得する（クラス参照比較より明示的）
        let selfIndex = sortedItems.firstIndex(where: { $0.id == self.id })

        // === Step 3: 自分の直後に挿入する order を sparseOrderForInsertion で算出 ===
        // 自分が見つからなければ末尾扱い。gap 不足時は内部で正規化される。
        let insertionIndex = (selfIndex ?? (sortedItems.count - 1)) + 1
        let newOrder = sparseOrderForInsertion(
            items: sortedItems,
            index: insertionIndex
        ) {
            normalizeSparseOrders(sortedItems)
        }

        // === Step 4: 新しい Item を作成 ===
        let newItem = M3Item(name: self.name,
                             memo: self.memo,
                             check: false,        // 進捗は引き継がない
                             stock: 0,            // 在庫もリセット
                             need: self.need,     // 必要数は引き継ぐ
                             weight: self.weight, // 個重量は引き継ぐ
                             order: newOrder,
                             parent: parent)
        // DB追加
        mc.insert(newItem)

        // === Step 5: 親グループの Item の order を正規化 ===
        // sparseOrderForInsertion で衝突しない order を得ているが、
        // 長期運用で order が大きな値になり過ぎるのを防ぐため正規化を実行。
        // （Fix 6 適用後は実質的に「ハウスキーピング」目的だが、副作用なく安全）
        parent.normalizeItemOrder()
    }

}

