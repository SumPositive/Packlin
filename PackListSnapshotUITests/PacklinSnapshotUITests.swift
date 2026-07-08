//
//  PacklinSnapshotUITests.swift
//  PackListSnapshotUITests  ← スクショ専用の UITest ターゲット
//
//  fastlane snapshot 用の UI テスト。
//  ※ 撮影専用ターゲットに置くことで、通常の Test 実行（Cmd+U / 既存 PackListUITests）
//    では一切走らない。撮影は fastlane（capture_screenshots）からのみ起動する。
//
//  ※ 現状はまず「起動直後のパック一覧 1 カット」だけ撮る検証用の骨組み。
//    撮影カット（グループ一覧・アイテム縦覧・設定など）は実機UIを見ながら
//    accessibilityIdentifier を付与しつつ順次追加する。
//
//  言語切替の方針（DialSplit / CreditMemo と同じ）:
//   - 言語は SnapshotHelper が language.txt の値で -AppleLanguages に設定済み。
//     ここでは上書きしない。
//   - ProcessInfo.environment["FASTLANE_LANGUAGE"] は UITest ランナーには
//     継承されず空になるので使わない。グローバル変数 deviceLanguage を読む。
//
//  ※ CreditMemo と違い通貨表示は無いため、通貨ロケール処理は持たない。
//

import XCTest

final class PacklinSnapshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTakeScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        // パック一覧が描画されるまで待つ
        sleep(2)

        // 1 カット目: パック一覧（メイン画面）
        snapshot("01PackList")

        // TODO: カットを増やす場合はここに追記する。
        //   例) グループ一覧へ遷移して snapshot("02GroupList") など。
        //   遷移は accessibilityIdentifier を付けてから、CreditMemo の openMenu の
        //   ように識別子タップで行うのが安定する。
    }
}
