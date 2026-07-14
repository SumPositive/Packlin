//
//  SnapshotSupport.swift
//  PackList
//
//  fastlane snapshot（スクショ自動撮影）実行中かどうかを判定するヘルパー。
//  SnapshotHelper が起動引数 -FASTLANE_SNAPSHOT YES を付けるので、それを読む。
//  撮影時だけ広告を隠したり、公開パック一覧にサンプルを流し込むために使う。
//

import Foundation

enum SnapshotSupport {
    /// fastlane snapshot による撮影中なら true。
    /// SnapshotHelper が UserDefaults 経由で -FASTLANE_SNAPSHOT YES をセットする。
    static var isRunningSnapshot: Bool {
        UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT")
    }
}
