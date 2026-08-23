# Packlin Android 対応 方針

作成日: 2026-08-23

---

## 1. 基本方針

**iOS と Android は共通化しない。それぞれのプラットフォームで最適・最効率・安全な実装を採り、操作性も個別に最適化する。**

共通化するのは以下のみ：

| 共通化する | 内容 |
|---|---|
| **API** | azuki-api（公開パックの公開／取込、AdMob SSV など） |
| **Exp/Imp JSON** | `.packlin` ファイル形式（パック共有・バックアップ） |
| **上記2つの仕様書** | 本ドキュメント（解釈のズレを防ぐ） |

共通化**しない**もの：

- ビジネスロジック（KMP / SQLDelight 等は採用しない）
- DB スキーマ（iOS は SwiftData のまま、Android は Room 等で最適に）
- UI（SwiftUI / Jetpack Compose でそれぞれネイティブに）

### 採否の理由

**規模が小さい**
Packlin のロジックは実質「3階層（Pack / Group / Item）の CRUD ＋ 並べ替え ＋ 集計」。KMP や共通レイヤの導入コストが、共有できるロジック量に見合わない。共有の旨みが出るのは複雑なドメインルール（料金計算、同期のコンフリクト解決など）を抱えたアプリで、Packlin はそこにいない。

**運用体制に合う**
5アプリを一人で回しており、ビルド環境も fastlane も iOS 前提で固まっている。ここに Gradle 連携や KMP のビルド事情を持ち込むと、Packlin 以外の4アプリの運用まで巻き込んで複雑になる。分離しておけば Android が転んでも iOS 側は無傷。

**操作性の要求が違う**
パッキングリストは「並べ替え・チェック・スワイプ削除」が主操作で、iOS と Android で作法がまるで違う。共通 UI にすると両方で微妙に浮く。

---

## 2. iOS 側の結論：現状維持

**SwiftData のまま。SQLite への移行もリポジトリ層の挿入も行わない。**

- Android と DB を揃える必要がないため、SQLite 移行の動機が消える
- リポジトリ層は「将来 SQLite に差し替える」ためのものなので、同じく不要
- Packlin はローカルのみ・単純な3階層・小データ量で、SwiftData の不安定さが出る領域（CloudKit 同期・複雑クエリ・重い一括更新）の外側にいる
- 現状の規模（Pack 30 / Group 30 / Item 100）では性能上の問題は発生しない

### 例外：将来 iOS 側で手を入れるなら

`stock` / `need` / `stockWeight` / `needWeight` は `child.reduce` による Swift 側集計。上限が Pack 30 × Group 30 × Item 100 に制限されているため現状は問題ないが、上限を緩めるときは集計値のキャッシュを検討する。

---

## 3. 現状の実装（Android 実装時の参照元）

Android 側を書くときに合わせるべき、iOS 側の既存実装。

### 3-1. データ構造（3階層）

```
M1Pack   … パック（旅行/用途の単位）
 └ M2Group … グループ（カテゴリ）
    └ M3Item  … アイテム（持ち物）
```

主なフィールド：

| モデル | フィールド |
|---|---|
| **M1Pack** | `id: String`, `order: Int`, `name`, `memo`, `createdAt`, `publishedId: String?` |
| **M2Group** | `id: String`, `order: Int`, `name`, `memo` |
| **M3Item** | `id: String`, `order: Int`, `name`, `memo`, `check: Bool`, `stock: Int`, `need: Int`, `weight: Int` |

- `publishedId` … 公開済みパックのサーバ側 ID。`nil` なら未公開、値があれば「公開中」
- 削除は cascade（Pack 削除で配下 Group / Item も削除）
- 集計値（`stock` / `need` / `stockWeight` / `needWeight`）は子の合計。DB には持たない導出値

### 3-2. 上限値（`Config.swift`）

Android 側も同一の上限を適用すること。取込時のクランプに使う。

```
APP_MAX_PACK_ROWS   = 30      // パック数
APP_MAX_PART_ROWS   = 30      // グループ数（1パックあたり）
APP_MAX_ITEM_ROWS   = 100     // アイテム数（1グループあたり）

APP_MAX_NAME_LEN    = 200     // name 文字数
APP_MAX_MEMO_LEN    = 200     // memo 文字数

APP_MAX_WEIGHT_NUM  = 999999  // 重量 (g)
APP_MAX_STOCK_NUM   = 999     // 在庫個数
APP_MAX_NEED_NUM    = 999     // 必要個数

ORDER_SPARSE        = 1000    // 並び順のスパース間隔
```

### 3-3. `order` の扱い（最重要・間違えやすい）

**スパース採番を使う。連番（0,1,2…）ではない。**

- 新規採番は `index * ORDER_SPARSE`（= 0, 1000, 2000, …）
- 挿入時は前後の中間値を使い、全行の更新を避ける
- **並び順の真実源は `order` のみ。配列やリレーションの並び順は意味を持たない**
- 表示時は必ず `ORDER BY order, id` 相当で安定ソートする（`order` 同値時は `id` でタイブレーク）

> iOS 側では SwiftData のリレーション配列の順序が保証されないため、`normalizeGroupOrder()` で「`order` と `id` で安定ソートしてから再採番、配列自体は触らない」という実装になっている。Android で素直に連番実装すると、**同じパックを両OSで往復させたときに並び順が変わる**ので注意。

### 3-4. `id` の生成規則

`shortUUID()` — **22文字の URL-safe Base64 文字列**。

生成手順（`ShortUUID.swift`）：

1. `UUID()` の文字列表現（36文字 ASCII）を UTF-8 バイト列に変換
2. SHA-256 でハッシュ（32バイト）
3. Base64 エンコード（44文字）
4. RFC 4648 §5 の URL-safe 変換：`+` → `-`、`/` → `_`、パディング `=` を除去
5. 先頭 22 文字を切り出す

> UUID をハッシュに通すのは、UUID v4 のランダム部分が偏っても Base64 表現が均一に分布するようにするため。
> **Android 側も同じ規則で生成すること。** 別形式の ID を吐くと、サーバ側の公開パックで衝突または識別不能が起きる。

---

## 4. Exp/Imp JSON 仕様

拡張子: `.packlin`（`PACK_FILE_EXTENSION`）

### 4-1. ヘッダ（バージョン管理は既に実装済み）

すべての `.packlin` ファイルは以下のヘッダを持つ：

| キー | 定数 | 現在値 | 用途 |
|---|---|---|---|
| `ProductName` | `PACK_JSON_DTO_PRODUCT_NAME` | `"Packlin"` | 生成元アプリの出自判定 |
| `copyright` | `PACK_JSON_DTO_COPYRIGHT` | `"2025_sumpo@azukid.com"` | 差異があれば読み込みエラー |
| `version` | `PACK_JSON_DTO_VERSION` | `"3.0"` | マイグレーション用 |

**検証は実装済み**（`AppMain.swift:271-272`, `SettingView.swift:726/757/809-812`）。
3項目すべてが一致しない場合は読み込みエラーとする。

> **注意**: 現状の検証は完全一致。Android 版が先に新バージョンを吐くと iOS 版が読めなくなる（黙って壊れるのではなく明示エラーになるので安全側）。両OSの対応バージョンを揃えてからリリースすること。

### 4-2. 構造

```jsonc
{
  "ProductName": "Packlin",
  "copyright": "2025_sumpo@azukid.com",
  "version": "3.0",
  "id": null,          // 共有時は null（読み込み側で生成）／バックアップ時のみ実IDを保持
  "order": null,       // 常に null（読み込み側で決定）
  "name": "北海道旅行",
  "memo": "",
  "createdAt": "2025-09-23T…",
  "groups": [
    {
      "id": null,      // 共有時は null
      "order": null,
      "name": "衣類",
      "memo": "",
      "items": [
        {
          "id": null,
          "order": null,
          "name": "Tシャツ",
          "memo": "",
          "check": false,
          "stock": 0,   // 任意。取込時は 0 リセットが原則
          "need": 3,
          "weight": 150
        }
      ]
    }
  ]
}
```

**全パックのバックアップ**は `BackupJsonDTO` でラップする：

```jsonc
{
  "ProductName": "Packlin",
  "copyright": "2025_sumpo@azukid.com",
  "version": "3.0",
  "exportedAt": "2025-09-23T…",
  "packs": [ /* PackJsonDTO の配列 */ ]
}
```

### 4-3. エクスポート時のルール

| 用途 | `id` | `order` | `stock` |
|---|---|---|---|
| **共有**（`exportRepresentation`） | `null` | `null` | 実値を出力 |
| **バックアップ**（`backupRepresentation`） | Pack のみ実 ID | `null` | 実値を出力 |

- Group / Item の `id` は共有・バックアップとも `null`（読み込み側で生成）
- Pack の `id` をバックアップだけ保持するのは、復元時に同一パックを照合して重複を防ぐため
- `groups` / `items` は出力時に `order` 昇順でソート済み

### 4-4. インポート時のルール（`PackImporter.swift`）

**ソート**
1. 配列を index 付きにする
2. `order` があれば `order`、なければ `index * ORDER_SPARSE` で比較
3. 同値時は元の index でタイブレーク（JSON の並びを忠実に再現）

**件数クランプ**（超過分は単純に切り捨て）
- Group: 先頭 `APP_MAX_PART_ROWS`(30) 件
- Item: 先頭 `APP_MAX_ITEM_ROWS`(100) 件

**値のクランプ**
- `name` / `memo` … 200 文字で切り詰め
- `stock` / `need` … 0〜999
- `weight` … 0〜999999
- `createdAt` … 妥当な範囲にクランプ

**再採番**
- 取込後の `order` は `index * ORDER_SPARSE` で振り直す

**`stock` の扱い**
- **通常の取込では `stock` を 0 にリセットするのが原則**
- **バックアップ復元時のみ元の値を尊重**（ただし範囲クランプは実施）

### 4-5. 未知フィールドの扱い（要決定）

現状 Swift の `Codable` は**未知のキーを黙って捨てる**。

片方の OS が先にフィールドを追加した場合、古い方で読み書きするとその情報が失われる。以下のいずれかを決めておくこと：

- **案A（推奨・単純）**: `version` の完全一致チェックがあるので、新フィールド追加時は必ず `version` を上げ、両OS同時対応する。未知フィールドの保持は考えない
- **案B**: 未知フィールドを保持して書き戻す（Swift 側は追加実装が必要）

> 現状の実装は実質「案A」。この方針を明文化して維持するのが最も安全。

---

## 5. 事前に決めておくべきこと

### 5-1. `userId` の扱い（最重要）

**iOS は `userId` を iCloud KVS（`NSUbiquitousKeyValueStore`）に保存し、端末故障後も復元できるようにしている。Android には iCloud KVS がない。**

決めるべき点：

1. **Android 側の `userId` 永続化方法**
   - Google の Auto Backup / Blocks Backup を使うか
   - サーバ側でアカウント紐付けするか
   - どちらも使わず端末ローカルのみとするか（＝機種変で引き継げない）

2. **同一ユーザーが iPhone と Android を併用した場合**
   - 同じ `userId` になるべきか、別扱いか
   - 別扱いにすると、公開パックの所有権（`publishedId` の取消権限）が分かれる

3. **取込広告ゲートのカウント**
   - 「公開パック取込3回ごとにリワード広告視聴を必須化」のカウントがサーバ側 `userId` に紐づくなら、上記が曖昧だと**カウントがリセットされたり二重になったりする**

> これは API 仕様に直結するため、**Android を書き始める前に決めること。**

### 5-2. 往復テスト用のサンプル JSON

両OSで「読んで書き戻して一致する」ことを確認する固定データを用意する。最低限このケースを含める：

- `order` が飛び飛び（スパース）のパック
- `order` が `null` のパック（共有形式）
- `order` が同値で重複しているパック（タイブレーク確認）
- 上限ちょうど（Group 30 / Item 100）のパック
- 上限超過（Group 31 / Item 101）のパック → 切り捨て確認
- `name` / `memo` が 200 文字超 → 切り詰め確認
- `stock` / `need` / `weight` が範囲外 → クランプ確認
- バックアップ形式（`BackupJsonDTO`、Pack の `id` あり）

---

## 6. 作業順（Android 着手時）

1. **`userId` の方針を決定**（5-1）— API 仕様に影響するため最初
2. **往復テスト用サンプル JSON を作成**（5-2）— iOS 側で先に生成し、正解データとして固定
3. **iOS 側で往復テストを通す** — 既存実装が仕様書どおりか検証（仕様書の誤りをここで洗い出す）
4. **Android 実装** — Room 等で最適に。UI は Jetpack Compose でネイティブに
5. **Android 側で同じ往復テストを通す** — サンプル JSON が両OSで同一結果になることを確認
6. **API 疎通** — 公開／取込／AdMob SSV

---

## 7. 参照ファイル（iOS 側）

| ファイル | 内容 |
|---|---|
| `PackList/Model/PackJsonDTO.swift` | Exp/Imp の DTO 定義・エクスポート変換 |
| `PackList/Model/PackImporter.swift` | インポート・サニタイズ・クランプ・再採番 |
| `PackList/Model/ShortUUID.swift` | `id` 生成規則 |
| `PackList/Model/M1Pack.swift` | Pack モデル・`order` 正規化・複製 |
| `PackList/Model/M2Group.swift` | Group モデル |
| `PackList/Model/M3Item.swift` | Item モデル |
| `PackList/Model/AzukiApi.swift` | API クライアント |
| `PackList/App/Config.swift` | 上限値・定数・API ベース URL |
| `PackList/App/AppMain.swift` | サンプルパック読込・ヘッダ検証 |
| `PackList/View/SettingView.swift` | バックアップ／復元 UI・ヘッダ検証 |
