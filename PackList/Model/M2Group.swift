//
//  M2Group.swift
//  PackList
//　　　 データ量的には3次元配列で十分だが、逐次保存など堅牢にするためにDBにする
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M2Group {  // "Group"ではSwiftUI.Groupと競合するため"M2"を付与することになった"M"はModel
    typealias ID = String
    @Attribute(.unique) var id: ID
    var order: Int

    var name: String
    var memo: String

    @Relationship(inverse: \M1Pack.child) var parent: M1Pack?
    @Relationship(deleteRule: .cascade) var child: [M3Item] = []

    var stock: Int { child.reduce(0) { $0 + $1.stock } }
    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.weight * $1.stock } }
    var needWeight: Int { child.reduce(0) { $0 + $1.weight * $1.need } }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         order: Int = 0,
         parent: M1Pack? = nil) {
        self.id = id
        self.name = name
        self.memo = memo
        self.order = order
        self.parent = parent
    }

    /// 子アイテムの order を連番に整理する
    /// - Note: order を唯一の真実源とする方針のため、child 配列の順序は変更しない。
    func normalizeItemOrder() {
        // order と id で安定ソートした配列に対してスパース再採番を適用する
        let sorted = child.sorted { ll, rr in
            if ll.order != rr.order {
                return ll.order < rr.order
            }
            return ll.id < rr.id
        }
        // 配列に触れず order のみを調整する
        normalizeSparseOrders(sorted)
    }

    /// 次の order 値を取得する
    func nextItemOrder() -> Int {
        let ordered = child.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            // 正規化時も order のみ操作する
            normalizeSparseOrders(ordered)
        }
    }
    
    /// 現在の Group を削除し、親パック配下の Group の order を再正規化する
    ///
    /// === 削除の流れ ===
    ///   1. 親パックの persistentModelID を退避（順序調整の対象を後で取り直すため）
    ///   2. 配下のアイテムをすべて削除（cascade で自動削除されるが、明示的に行う）
    ///   3. 自分自身を削除
    ///   4. 親パックを再フェッチして normalizeGroupOrder() を呼び、order を 0, 1000, 2000... に振り直す
    ///
    /// === Fix 4: 親パックを「参照保持」ではなく「ID 退避→再フェッチ」にする理由 ===
    /// 修正前は以下のようになっていた：
    /// ```
    /// let parentPack = self.parent          // 参照を保持
    /// mc.delete(self)
    /// parentPack?.normalizeGroupOrder()      // 古い child を見たまま正規化
    /// ```
    /// この実装には次の問題があった：
    ///   - `mc.delete(self)` の直後、SwiftData は `parentPack.child` 配列から
    ///     `self` を除外する更新を非同期に行う場合がある（実装詳細）。
    ///   - そのため `normalizeGroupOrder()` 内で `child` を走査したときに、
    ///     **削除済みの自分がまだ残ったまま order を再採番する**可能性がある。
    ///   - 結果として「削除したはずのグループの order が他の生きているグループを
    ///     押しのける」など、UI と DB の表示順がズレる事故が起こり得た。
    ///
    /// 修正後の実装では、`persistentModelID` を退避してから削除し、
    /// 削除後に **同じパックを ID で再フェッチ** してから `normalizeGroupOrder()`
    /// を呼ぶ。再フェッチによって `child` のキャッシュが最新化されるため、
    /// 削除済みグループを含まない正確な状態で order が振り直される。
    ///
    /// （同じパターンが M3Item.delete() でも既に採用されていたので、
    /// それに揃える形での修正でもある。）
    func delete() {
        guard let mc = modelContext else {return}

        // === Step 1: 親パックの ID を退避 ===
        // self.parent を変数に保持しても、後で normalize したときに
        // 古いキャッシュを見てしまうリスクがあるため、`persistentModelID`
        // という識別子だけを保存しておく。
        let parentPackID = self.parent?.persistentModelID

        // === Step 2: 配下のアイテムを削除 ===
        // SwiftData の @Relationship 配列はイテレーション中に内部状態が
        // 変化する可能性があるため、Array(...) で明示コピーしてから for-in する。
        // （詳細は PackImporter.overwrite のコメントを参照）
        let items = Array(self.child)
        for item in items {
            mc.delete(item)
        }

        // === Step 3: 自身を削除 ===
        // 上で配下を消してあるが、念のため cascade ルールでも保護される設計。
        mc.delete(self)

        // === Step 4: 親パックを再フェッチして order を正規化 ===
        // ここが Fix 4 の核心。退避しておいた persistentModelID で
        // 親パックを再取得することで、自分が削除された後の最新 child 配列
        // を含んだ Pack インスタンスを得る。
        if let parentPackID {
            let descriptor = FetchDescriptor<M1Pack>(
                predicate: #Predicate { element in
                    element.persistentModelID == parentPackID
                }
            )
            // fetch 失敗時は親が既に削除されたケースなので order 整理は不要。
            // try? で安全側に倒す。
            if let reloadedParent = try? mc.fetch(descriptor).first {
                reloadedParent.normalizeGroupOrder()
            }
        }
    }

    /// 現在の Group を複製し、現在の行のすぐ下に追加する
    ///
    /// 複製仕様:
    ///   - 新しいグループは元と同じ name / memo を持つ
    ///   - 新しい Group の order は **`sparseOrderForInsertion` で「自分と次の Group の中間」を計算**
    ///     （Fix 6 で改善。旧版の `self.order + 1` は隣接 Group の order と衝突する可能性があった）
    ///   - 配下の各 Item も新規生成して新グループに紐付ける
    ///   - 複製したアイテムは check=false / stock=0 にリセット（need と weight は維持）
    ///     → 複製は「テンプレートとして使い回したい」想定なので、進捗系はリセットするのが妥当
    ///
    /// === Fix 6: order 一時衝突の対策 ===
    /// 旧版は `order: self.order + 1` で挿入していたが、隣接 Group の order と
    /// 衝突する可能性があり、`normalizeGroupOrder` 後の並びが id タイブレークで
    /// 不定になる事故があった。詳細は M1Pack.duplicate() のコメント参照。
    /// 新版は `sparseOrderForInsertion` で「自分と次の Group の中間」を計算する。
    func duplicate() {
        guard let mc = modelContext else {return}
        // 親 Pack が無いグループは複製不可（通常は起こらないが、防御的に return）
        guard let parent = self.parent else { return }

        // === Step 1: 親パック配下の Group を order でソートして並び順を確定 ===
        // parent.child は SwiftData リレーションシップで順序が保証されないため、
        // 自分の次のグループを特定するためにここで明示ソートしておく。
        let sortedGroups = parent.child.sorted { $0.order < $1.order }

        // === Step 2: 自分のインデックスを特定する ===
        // id 比較で確実に自分の位置を取得する（クラス参照比較より明示的）
        let selfIndex = sortedGroups.firstIndex(where: { $0.id == self.id })

        // === Step 3: 自分の直後に挿入する order を sparseOrderForInsertion で算出 ===
        // 自分が見つからなければ末尾扱い。gap 不足時は内部で正規化される。
        let insertionIndex = (selfIndex ?? (sortedGroups.count - 1)) + 1
        let newOrder = sparseOrderForInsertion(
            items: sortedGroups,
            index: insertionIndex
        ) {
            normalizeSparseOrders(sortedGroups)
        }

        // === Step 4: 新しい Group を作成 ===
        let newGroup = M2Group(name: self.name,
                               memo: self.memo,
                               order: newOrder,
                               parent: parent)
        mc.insert(newGroup)

        // === Step 2: 配下の Item をすべて複製 ===
        // SwiftData の @Relationship は context.insert() によって暗黙的に
        // 親の child 配列が更新されることがある。たとえば newItem を insert すると
        // parent (= newGroup) の child が変わり、これが連鎖的にメモリ上の
        // 他のリレーションシップ状態にも影響を与える可能性がある。
        //
        // そのためイテレーション対象 self.child を Array(...) でスナップショット化し、
        // ループ中に self.child が SwiftData によって変動しても影響を受けないようにする。
        let items = Array(self.child)
        for item in items {
            let newItem = M3Item(name: item.name,
                                 memo: item.memo,
                                 check: false,        // 進捗は引き継がない
                                 stock: 0,            // 在庫もリセット
                                 need: item.need,     // 必要数は引き継ぐ
                                 weight: item.weight, // 個重量は引き継ぐ
                                 order: item.order,
                                 parent: newGroup)
            mc.insert(newItem)
        }

        // === 最終 Step: 親パックの Group の order を正規化（ハウスキーピング） ===
        // Fix 6 適用後は sparseOrderForInsertion で衝突しない order を得ているため、
        // このタイミングでの normalize は「必須」ではなく「長期運用での order 数値が
        // 大きくなりすぎないようにする」ためのハウスキーピング目的。
        // 副作用なく安全に呼べるので、従来通り実行しておく。
        parent.normalizeGroupOrder()
    }

}

