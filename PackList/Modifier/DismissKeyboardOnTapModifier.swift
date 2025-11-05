import SwiftUI
import UIKit

/// TextEditorなどのキーボード入力中に、入力欄の外をタップしたときだけフォーカスを外すためのモディファイア
/// UIViewRepresentableを用いてUIKitのタップ判定を行い、TextEditor内部のタップは無視する
struct DismissKeyboardOnTapModifier: ViewModifier {
    /// 外部から受け取るフォーカス制御用のバインディング
    /// - Note: TextEditorにのみフォーカスが当たっているときにfalseへ切り替えてキーボードを閉じる
    var requirementFocus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            // ScrollView全体に透明なUIViewを重ね、UIKitのGestureRecognizerでタップ位置を判定する
            .background(DismissKeyboardRepresentable(requirementFocus: requirementFocus))
    }
}

private struct DismissKeyboardRepresentable: UIViewRepresentable {
    /// SwiftUI側のフォーカス状態を共有するためのバインディング
    var requirementFocus: FocusState<Bool>.Binding

    func makeUIView(context: Context) -> UIView {
        // 透明なUIViewを生成し、ScrollViewの背景として配置する
        let view = UIView()
        view.backgroundColor = .clear

        // タップ検知用のジェスチャレコグナイザを追加
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        // TextEditorなど既存のタップ処理を妨げないように、cancelsTouchesInViewをfalseへ設定
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Coordinatorへ最新のフォーカス状態を共有
        context.coordinator.requirementFocus = requirementFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(requirementFocus: requirementFocus)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// SwiftUIのフォーカス状態を保持するバインディング
        var requirementFocus: FocusState<Bool>.Binding

        init(requirementFocus: FocusState<Bool>.Binding) {
            self.requirementFocus = requirementFocus
            super.init()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // タップが完了したタイミングのみ処理する
            guard gesture.state == .ended else {
                return
            }

            // TextEditorがフォーカス中であれば、遅延実行でフォーカスを外してキーボードを閉じる
            if requirementFocus.wrappedValue {
                DispatchQueue.main.async {
                    requirementFocus.wrappedValue = false
                    // 第一レスポンダへresignFirstResponderを送信し、確実にキーボードを閉じる
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // タップされたUIViewがTextEditor(=UITextView)の内部であればfalseを返してスキップする
            var currentView: UIView? = touch.view
            while let view = currentView {
                if view is UITextView {
                    return false
                }
                currentView = view.superview
            }
            return true
        }
    }
}

extension View {
    /// TextEditorなどの入力欄外をタップしたときだけキーボードを閉じるヘルパー
    /// - Parameter requirementFocus: フォーカス状態を共有するFocusStateのバインディング
    func dismissKeyboardOnTapOutside(requirementFocus: FocusState<Bool>.Binding) -> some View {
        modifier(DismissKeyboardOnTapModifier(requirementFocus: requirementFocus))
    }
}
