//
//  PacklinSnapshotUITests.swift
//  PackListSnapshotUITests  ← スクショ専用の UITest ターゲット
//
//  fastlane snapshot 用の UI テスト。
//  ※ 撮影専用ターゲットに置くことで、通常の Test 実行（Cmd+U / 既存 PackListUITests）
//    では一切走らない。撮影は fastlane（capture_screenshots）からのみ起動する。
//
//  撮影カット:
//    01PackList      … パック一覧（起動直後。サンプルパックが投入済み）
//    02GroupList     … 先頭パックのグループ一覧
//    03ItemList      … 先頭グループのアイテム一覧
//    04PublicGallery … 公開パックから取得（撮影時はサンプル一覧・広告なし）
//
//  遷移はアプリ側に付けた accessibilityIdentifier をタップして行う（ja/en 両対応）:
//    packRow_first_open  / groupRow_first_open / packAdd_button / packAdd_publicGallery
//
//  言語切替の方針（DialSplit / CreditMemo と同じ）:
//   - 言語は SnapshotHelper が language.txt の値で -AppleLanguages に設定済み。ここでは上書きしない。
//   - 通貨表示は無いため通貨ロケール処理は持たない。
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

        // 01: パック一覧
        snapshot("01PackList")

        // 02: 先頭パック → グループ一覧
        if tap(app, "packRow_first_open") {
            sleep(2)
            snapshot("02GroupList")

            // 03: 先頭グループ → アイテム一覧
            if tap(app, "groupRow_first_open") {
                sleep(2)
                snapshot("03ItemList")
            }
        }

        // 04: パック一覧へ戻ってから、公開パックから取得（サンプル・広告なし）
        popToRoot(app)
        if tap(app, "packAdd_button") {
            sleep(1)
            if tap(app, "packAdd_publicGallery") {
                sleep(2)
                snapshot("04PublicGallery")
            }
        }
    }

    /// 識別子の要素（button / cell / other / link を横断）が見えたらタップする。
    @MainActor
    @discardableResult
    private func tap(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 8) -> Bool {
        let candidates = [
            app.buttons[identifier],
            app.otherElements[identifier],
            app.cells[identifier],
            app.links[identifier]
        ]
        for element in candidates where element.waitForExistence(timeout: 2) {
            if element.isHittable {
                element.tap()
                return true
            }
        }
        // どれも hittable でない場合、最初に存在した要素を timeout まで待って叩く
        let primary = app.buttons[identifier]
        if primary.waitForExistence(timeout: timeout) {
            primary.tap()
            return true
        }
        return false
    }

    /// パック一覧（ルート）まで戻る。iPhone は push を戻り、iPad は既に見えている。
    @MainActor
    private func popToRoot(_ app: XCUIApplication) {
        for _ in 0..<4 {
            // ルートにいれば先頭パック行の識別子が見えるはず
            if app.buttons["packRow_first_open"].waitForExistence(timeout: 1)
                || app.otherElements["packRow_first_open"].waitForExistence(timeout: 1) {
                break
            }
            let back = app.navigationBars.buttons.firstMatch
            if back.exists && back.isHittable { back.tap(); sleep(1) } else { break }
        }
    }
}
