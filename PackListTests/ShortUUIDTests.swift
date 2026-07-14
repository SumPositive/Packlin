//
//  ShortUUIDTests.swift
//  PackListTests
//
//  Fix 1（shortUUID の length 拡張）の動作検証。
//  - 既定値が 22 文字であること
//  - URL-safe な文字種で構成されていること
//  - 大量生成しても衝突しないこと（実用上の一意性）
//

import Testing
import Foundation
@testable import Packlin

struct ShortUUIDTests {

    @Test("shortUUID の既定値は 22 文字を返す")
    func defaultLengthIs22Characters() {
        let id = shortUUID()
        #expect(id.count == 22)
    }

    @Test("shortUUID は length 引数で短い ID も生成できる（旧 16 文字互換）")
    func canGenerateShorterIdForBackwardCompatibility() {
        let legacy = shortUUID(length: 16)
        #expect(legacy.count == 16)
    }

    @Test("shortUUID は URL-safe な文字種のみで構成される")
    func usesOnlyUrlSafeCharacters() {
        // URL-safe base64 は [A-Z], [a-z], [0-9], '-', '_' のみ
        let allowedSet = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        // 100 回生成して 1 文字も逸脱しないことを確認
        for _ in 0..<100 {
            let id = shortUUID()
            let idSet = CharacterSet(charactersIn: id)
            #expect(idSet.isSubset(of: allowedSet),
                    "Generated ID '\(id)' contains non-URL-safe characters")
        }
    }

    @Test("shortUUID は base64 のパディング '=' を含まない")
    func doesNotContainBase64Padding() {
        for _ in 0..<50 {
            let id = shortUUID()
            #expect(!id.contains("="))
        }
    }

    @Test("shortUUID は大量生成しても衝突しない（10,000 件で全件ユニーク）")
    func tenThousandIdsAreUnique() {
        // 22 文字 ≒ 2^132 のキースペースなら 10,000 件は衝突 0 が期待される
        var ids = Set<String>()
        for _ in 0..<10_000 {
            ids.insert(shortUUID())
        }
        #expect(ids.count == 10_000)
    }
}
