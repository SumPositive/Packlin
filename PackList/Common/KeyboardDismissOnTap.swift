//
//  KeyboardDismissOnTap.swift
//  PackList
//
//  文字入力欄の外をタップしたらキーボードを閉じる（アプリ全体共通）
//  ウインドウにタップ認識を1つ取り付け、タップを横取りせずに編集だけ終わらせる。
//  シートやアラートも同じウインドウ上に出るので、どの画面でも同じ動きになる
//

import SwiftUI
import UIKit

extension View {
    /// このビューが置かれたウインドウで、入力欄の外のタップでキーボードを閉じるようにする
    func dismissesKeyboardOnOutsideTap() -> some View {
        background(KeyboardDismissInstaller().allowsHitTesting(false))
    }
}

/// 入力欄の外のタップで編集を終えるタップ認識
/// - 他のボタンやリストのタップは止めない（cancelsTouchesInView = false、同時認識を許す）
/// - 入力欄（UITextField・UITextView など）の上のタップは対象外にして、入力欄の切り替えを妨げない
private final class KeyboardDismissTapGesture: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    // UIGestureRecognizer の指定イニシャライザは init(target:action:) なので、それを上書きして初期設定する
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        addTarget(self, action: #selector(handleTap))
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc private func handleTap() {
        view?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 入力欄（またはその内側）のタップは受けない
        var current = touch.view
        while let view = current {
            if view is UITextInput { return false }
            current = view.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// 置かれたウインドウに KeyboardDismissTapGesture を1つだけ取り付ける
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window,
                  !(window.gestureRecognizers ?? []).contains(where: { $0 is KeyboardDismissTapGesture }) else { return }
            window.addGestureRecognizer(KeyboardDismissTapGesture(target: nil, action: nil))
        }
    }
}
