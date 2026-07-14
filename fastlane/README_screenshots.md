# App Store スクリーンショットの自動撮影・アップロード（Packlin / モチメモ）

`fastlane snapshot` でシミュレータからスクショを自動撮影し、`deliver` でアップロードします。
**まずは「パック一覧 1 カット × ja/en-US × iPhone 17 Pro Max」で仕組みを検証**し、
動いたら言語・デバイス・カットを増やす方針です。

---

## ステップ 0: 用意済みファイル

以下を用意済みです:

- `fastlane/uitest/SnapshotHelper.swift` … fastlane 公式ヘルパー（Xcode 26 対応済みの版）
- `fastlane/uitest/PacklinSnapshotUITests.swift` … 撮影用 UI テスト（今はパック一覧 1 カットの骨組み）
- `fastlane/Snapfile` … 撮影対象の言語・デバイス設定
- `fastlane/Fastfile` … レーン `screenshots` / `upload_screenshots` / `screenshots_and_upload`

`fastlane/uitest/` の 2 つの .swift は「置き場所」です。次のステップで **スクショ専用の
新規 UITest ターゲット** に取り込みます。

> ⚠️ 既存の `PackListUITests` には入れません。専用ターゲットに分離することで、
> 通常の Test 実行（Cmd+U / CI）では撮影テストが一切走りません。

---

## ステップ 1: スクショ専用 UITest ターゲットを新設（← 手動 GUI 操作）

1. `Packlin.xcodeproj` を Xcode で開く
2. **File > New > Target…** → **UI Testing Bundle** を選択
3. 設定:
   - **Product Name**: `PackListSnapshotUITests`
   - **Target to be Tested**: `Packlin`
   - Team / Organization は他ターゲットに合わせる
4. 生成された `PackListSnapshotUITests/` 内の雛形 .swift（`...UITests.swift` /
   `...LaunchTests.swift`）は不要なので **削除**（Move to Trash）

> Snapfile の `only_testing` は
> `PackListSnapshotUITests/PacklinSnapshotUITests/testTakeScreenshots` を指しています。
> ターゲット名・クラス名・メソッド名がこの3つと一致している必要があります。
> 別名にする場合は Snapfile も合わせて変更してください。

---

## ステップ 2: ファイルを専用ターゲットに紐付け

1. `fastlane/uitest/PacklinSnapshotUITests.swift` を Xcode にドラッグして
   **PackListSnapshotUITests ターゲットにのみ**追加（Target Membership をこのターゲットだけにチェック）
2. `fastlane/uitest/SnapshotHelper.swift` も同様に
   **PackListSnapshotUITests ターゲットにのみ**追加

> SnapshotHelper.swift はアプリ本体や既存 PackListUITests には入れないこと（撮影専用）。
> `fastlane/uitest/` を編集したら Xcode 側の実体にも反映すること（両方同期）。

---

## ステップ 3: スキーム設定（テストを共有可能に）

1. Xcode の **Product > Scheme > Manage Schemes…**
2. `Packlin` スキームの **Shared** にチェックが入っていることを確認
3. **Edit Scheme… > Test** タブで、`PackListSnapshotUITests` がテスト対象に含まれていることを確認
   - 通常の Cmd+U で撮影を走らせたくない場合は、ここで `PackListSnapshotUITests` の
     チェックを **外して** おく（fastlane は `only_testing` で明示指定するので影響しない）

---

## ステップ 4: 撮影して確認（アップロードしない）

```sh
cd /Users/sumpositive/GitLocal/Packlin
fastlane screenshots
```

- 出力先: `fastlane/screenshots/<言語>/<デバイス>-01PackList.png`
- `fastlane/screenshots/screenshots.html` をブラウザで開くと一覧できる
- 0 枚のときは Snapfile の `only_testing` とターゲット/クラス/メソッド名の一致を疑う

### シミュレータ起動失敗（Clone の launch-failed 等）が出たら

```sh
xcrun simctl shutdown all
sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService
```
でクリーンにしてから再実行。Snapfile で `number_of_retries(3)` 済み。

---

## ステップ 5: アップロード（審査提出はしない）

```sh
# .env を用意（初回のみ）
cp fastlane/.env.example fastlane/.env
# .env に ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH を記入

fastlane upload_screenshots          # 撮影済みを ASC に反映（置き換え）
# または
fastlane screenshots_and_upload      # 撮影 → アップロードを一括
```

`submit_for_review(false)` なので App Store 審査には出さず、保存のみ。

---

## カットを増やすとき

`fastlane/uitest/PacklinSnapshotUITests.swift` の `testTakeScreenshots` に
`snapshot("02GroupList")` のように追記する。画面遷移は accessibilityIdentifier を
付けてから CreditMemo の `openMenu` のように識別子タップで行うのが安定する。
編集後は Xcode 側の実体にも反映すること。
