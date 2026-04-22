//
//  DatabaseErrorView.swift
//  PackList
//
//  Created by sumpo/azukid on 2026/03/28.
//

import SwiftUI

/// データベース初期化失敗時に表示するエラー画面
///
/// - Note: パックが消えた場合は、バックアップから復元してください。
///   アプリが保存したバックアップ（.store.bak）は
///   デバイスの Files アプリ → PackList アプリフォルダには表示されません。
///   Xcode の Devices ウィンドウや iTunes のファイル共有から取り出して復元できます。
/// - Note: 全パックを一括して JSON ファイルにエクスポート／インポートする機能を追加予定。
struct DatabaseErrorView: View {

    let error: Error?
    /// 破損ストアを .bak にリネームして次回起動時にクリーンな状態で再起動するためのコールバック
    let onReset: () -> Void

    @State private var showConfirmAlert = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("database.initialization.failed")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Text("data.may.be.corrupted.tapping.reset")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(role: .destructive) {
                showConfirmAlert = true
            } label: {
                Label("reset.restart", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
        .alert("reset.data", isPresented: $showConfirmAlert) {
            Button("reset", role: .destructive) {
                onReset()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("current.data.will.be.saved.bak")
        }
    }
}

#Preview {
    DatabaseErrorView(error: nil, onReset: {})
}
