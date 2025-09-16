//
//  Common.swift
//  PackList
//
//  Created by sumpo on 2025/09/16.
//

import UIKit
import Combine


var popoverBottom: CGFloat = 0

// キーボード高さを監視
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var cancellable: AnyCancellable?
    private var currentOverlap: CGFloat = 0
    private var currentWindowHeight: CGFloat = 0

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
                guard let self = self else { return }
                guard
                    let info = note.userInfo,
                    let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let window = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
                else {
                    self.currentOverlap = 0
                    self.currentWindowHeight = 0
                    self.height = 0
                    return
                }

                // 画面下端からキーボード上端までの差分（安全域は除外）
                let bottomInset = window.safeAreaInsets.bottom
                let overlap = max(0, window.bounds.maxY - end.minY - bottomInset)
                self.apply(overlap: overlap, windowHeight: window.bounds.maxY)
            }
    }

    func refresh() {
        apply(overlap: currentOverlap, windowHeight: currentWindowHeight)
    }

    private func apply(overlap: CGFloat, windowHeight: CGFloat) {
        currentOverlap = overlap
        currentWindowHeight = windowHeight

        guard overlap > 0, windowHeight > 0 else {
            height = 0
            return
        }

        let spaceBelowPopup = max(0, windowHeight - popoverBottom)
        if spaceBelowPopup < overlap {
            height = overlap - spaceBelowPopup
        } else {
            height = 0
        }
    }
}
