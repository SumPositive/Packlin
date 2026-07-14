# 公開パックのサンプル掲載手順（管理者用）

公開パックギャラリー（「公開パックから取得」）に、実サーバ経由で見映えの良いサンプルを
掲載するための手順です。スクショ撮影時はこのサーバ掲載データがそのまま表示されます。

- サンプル本体: このフォルダの `ja/*.packlin` と `en/*.packlin`（各12ジャンル）
- 生成元: `generate_sample_packs.py`（内容を直したいときはこれを編集して再実行）

```sh
cd /Users/sumpositive/GitLocal/Packlin
python3 fastlane/sample_packs/generate_sample_packs.py   # ja/en に24ファイルを再生成
```

---

## 仕組み（なぜこの手順か）

- 公開は `POST /api/packs/publish`（要 App Attest 認証）。サーバは `userId === auth.userId`
  を要求するため、**公開はアプリ（実機）からしか行えない**。
- 一覧に出る作者名は `users.nickname`。管理者デバイスの nickname を決めておけば、
  掲載したサンプルすべての作者名がそれになる。
- したがって「管理者用の特別な userId」＝**あなたの管理者デバイスの userId**。
  その端末で nickname を設定し、サンプルを読み込んで公開する、という運用にする。

---

## 手順

### 1. 管理者デバイスで作者名（nickname）を設定

アプリの nickname 設定（公開時に入力／設定画面）で、例えば
**「モチメモ公式」/「Packlin Official」** を設定する。以後この端末から公開する
パックの作者名がこれになる。

> nickname は `PATCH /api/user/nickname` で更新され、過去に公開した分にも即反映される。

### 2. サンプル .packlin を端末に取り込む

`ja/` または `en/`（端末の言語に合わせる）の `.packlin` を、AirDrop やファイルアプリ等で
管理者デバイスに送る。

アプリの **設定 → 「保存パックを読み込む」** から `.packlin` を選ぶとパックが追加される。
12ファイルまとめて読み込んでよい。

> locale はサーバ側で「公開した端末の言語」で記録される。日本語一覧に出したいものは
> **日本語端末（またはAppleLanguages=ja）で ja の .packlin を公開**、英語一覧に出したいものは
> 英語設定で en を公開する、と分けると綺麗（両方出したいジャンルは両言語で公開する）。

### 3. 各パックを公開する

追加された各パックを開き、**公開**する（パック編集画面の公開機能）。
12ジャンル分くり返す。公開済みのものは公開パックギャラリーに並ぶ。

### 4. 確認

「新しいパックを追加 → 公開パックから取得」を開き、掲載したサンプルが
一覧に出ることを確認する。並び順は人気（取得数）順・新着順。

---

## スクショ撮影との関係

- 撮影テスト（`fastlane/uitest/PacklinSnapshotUITests.swift`）の `04PublicGallery` は
  **実サーバから取得**して表示する（ローカルのサンプル埋め込みは廃止済み）。
- そのため、**撮影前にこの掲載を済ませておくこと**。掲載が空だと 04 は空一覧になる。
- 公開パック画面のバナー広告は、スクショ撮影時のみ非表示（審査用スクショに広告を写さないため）。

---

## メンテナンス

- ジャンルや中身を増減したいときは `generate_sample_packs.py` の `PACKS` を編集して再生成。
- 既に公開済みのものを差し替えるときは、いったん公開を取り消し（unpublish）てから
  新しい内容で再公開する（`source_pack_id` 単位で上書き判定される）。

---

## DB直接投入（管理者・上級者向け）

アプリ経由ではなく Neon(Postgres) の `published_packs` へ直接 upsert する方法。
本番DBに書き込むので取り扱い注意。接続文字列は `azuki-api/.dev.vars` の `DATABASE_URL`
から読む（スクリプトには書かない。`.dev.vars` は gitignore 済み）。

- `db_inspect.mjs` … 読み取り専用の状況確認（sumpoのuser_id・既存公開・payload形式）
- `db_publish_samples.mjs` … サンプル24件（ja/en 各12）を upsert
  - nickname=sumpo の実ユーザーに紐付け（**ja=8856f454… / en=57a0e4a0…**、DB調査で判明）
  - `source_pack_id` は `sample-<slug>`（手動公開分と衝突しない接頭辞）
  - payload の `createdAt` は ISO8601 文字列へ変換（アプリの .iso8601 デコードと整合）
  - search_text / payload_bytes / total_weight は publish ルートと同じ計算で埋める

```sh
cd /Users/sumpositive/GitLocal/azuki-api          # .dev.vars と node_modules がある場所で実行
node ../Packlin/fastlane/sample_packs/db_publish_samples.mjs           # ドライラン（書き込まない）
node ../Packlin/fastlane/sample_packs/db_publish_samples.mjs --commit  # 実投入（upsert）
```

> 2026-07-08 実行済み: 既存6件 + サンプル24件 = 公開30件（ja15 / en15、全て作者sumpo）。
> 再実行しても `(user_id, source_pack_id)` で upsert されるため重複しない。
