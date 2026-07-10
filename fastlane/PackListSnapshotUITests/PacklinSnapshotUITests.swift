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
//    04PublicGallery … 公開パックから取得（実サーバのサンプル・広告なし）
//
//  遷移の考え方:
//   - 先頭パック行/グループ行の遷移領域は透明な NavigationLink(Color.clear) で、
//     accessibilityIdentifier を付けても isHittable=false になり要素タップが空振りする。
//   - そこで identifier での element.tap() に加え、失敗時は「セル領域の座標を直接タップ」する
//     フォールバックを持たせる（coordinate(withNormalizedOffset:).tap() は hittable 判定を回避する）。
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
        sleep(2)

        // 01: パック一覧
        snapshot("01PackList")

        // 02: 先頭パック → グループ一覧
        // 先頭パック行の遷移領域（行の右寄り）をタップして push する。
        if tapFirstRowNavigation(app, identifier: "packRow_first_open") {
            sleep(2)
            snapshot("02GroupList")

            // 03: 先頭グループ → アイテム一覧
            if tapFirstRowNavigation(app, identifier: "groupRow_first_open") {
                sleep(2)
                snapshot("03ItemList")
            }
        }

        // 04: パック一覧へ戻ってから、公開パックから取得
        popToRoot(app)
        sleep(1)
        if tap(app, "packAdd_button") {
            sleep(1)
            // ポップオーバー内の「公開パックから取得」項目をタップ。
            // popover は別 presentation なので identifier だけでなく
            // ローカライズ文言・座標も含めて多段で拾う。
            if tapPublicGalleryOption(app) {
                sleep(3) // 実サーバ取得を待つ
                snapshot("04PublicGallery")
            }
        }
    }

    /// パック追加ポップオーバー内の「公開パックから取得」項目をタップする。
    @MainActor
    @discardableResult
    private func tapPublicGalleryOption(_ app: XCUIApplication) -> Bool {
        // ① identifier で（button/other/cell 横断）
        let byId: [XCUIElement] = [
            app.buttons["packAdd_publicGallery"],
            app.otherElements["packAdd_publicGallery"],
            app.cells["packAdd_publicGallery"]
        ]
        for e in byId where e.waitForExistence(timeout: 3) {
            if e.isHittable { e.tap(); return true }
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        // ② ローカライズ文言で（ja/en）。public.pack.gallery.title の実文言。
        for label in ["公開パックから取得", "Get from public packs"] {
            let byLabel = app.buttons[label]
            if byLabel.waitForExistence(timeout: 1) {
                byLabel.tap(); return true
            }
            let staticText = app.staticTexts[label]
            if staticText.exists {
                staticText.tap(); return true
            }
        }
        return false
    }

    /// 先頭行の遷移をタップする。
    /// ①identifier 要素が hittable ならそれをタップ。
    /// ②ダメなら、先頭セル（または画面上部のリスト領域）の右寄りの座標を直接タップする。
    @MainActor
    @discardableResult
    private func tapFirstRowNavigation(_ app: XCUIApplication, identifier: String) -> Bool {
        // ① identifier 要素（button/link/other/cell 横断）が hittable ならタップ
        let candidates: [XCUIElement] = [
            app.buttons[identifier],
            app.links[identifier],
            app.otherElements[identifier],
            app.cells[identifier]
        ]
        for element in candidates where element.exists {
            if element.isHittable {
                element.tap()
                return true
            }
            // 存在するが hittable でないときは、その要素の座標中央付近をタップ
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }

        // ② identifier が取れないとき: リスト先頭セルの右寄りを座標タップ
        //   セルが列挙できればそれを、なければ画面上部の行帯を狙う。
        let firstCell = app.cells.element(boundBy: 0)
        if firstCell.waitForExistence(timeout: 5) {
            // 右2/3が遷移領域なので、右寄り(dx=0.75)・縦中央(dy=0.5)を叩く
            firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
            return true
        }
        // セルも取れない場合の最終手段: 画面全体の上部・右寄りを座標タップ
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.28))
        point.tap()
        return true
    }

    /// 識別子の要素が見えたらタップする（可視ボタン向け。packAdd 系）。
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
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        let primary = app.buttons[identifier]
        if primary.waitForExistence(timeout: timeout) {
            primary.tap()
            return true
        }
        return false
    }

    /// パック一覧（ルート）まで戻る。
    @MainActor
    private func popToRoot(_ app: XCUIApplication) {
        for _ in 0..<4 {
            if app.buttons["packAdd_button"].waitForExistence(timeout: 1) {
                break
            }
            let back = app.navigationBars.buttons.firstMatch
            if back.exists && back.isHittable { back.tap(); sleep(1) } else { break }
        }
    }
}
