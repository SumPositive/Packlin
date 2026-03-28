//
//  Common.swift
//  PackList
//
//  Created by sumpo on 2025/09/16.
//

import UIKit
import Combine

// iPadのマルチウィンドウでタイトルバー左上のシステムボタンがヘッダーを覆うのを避けるための余白を返す
func ipadWindowControlInset() -> CGFloat {
    if UIDevice.current.userInterfaceIdiom == .pad {
        return IPAD_WINDOW_CONTROL_INSET
    }
    return 0
}


// キーボード高さを監視
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    /// ポップオーバーの下端Y座標。設定すると次回のキーボード通知で高さが再計算される
    @Published var popoverBottom: CGFloat = 0
    private var cancellable: AnyCancellable?

    init() {
        let willChange = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification
        )
        .merge(with: NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        ))

        cancellable = willChange
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard
                    let info = note.userInfo,
                    let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let window = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
                else {
                    self.height = 0
                    return
                }

                // 画面下端からキーボード上端までの差分（安全域は除外）
                let bottomInset = window.safeAreaInsets.bottom
                let overlap = max(0, window.bounds.maxY - end.minY - bottomInset)

                if (window.bounds.maxY - self.popoverBottom) < overlap {
                    self.height = overlap - (window.bounds.maxY - self.popoverBottom)
                } else {
                    self.height = 0
                }
            }
    }
}
