import SwiftUI
import Combine
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published private(set) var keyboardHeight: CGFloat = 0

    private var willShowObserver: AnyCancellable?
    private var willHideObserver: AnyCancellable?

    init() {
        willShowObserver = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue }
            .map { $0.cgRectValue.height }
            .sink { [weak self] height in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = height
                }
            }

        willHideObserver = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat.zero }
            .sink { [weak self] _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = 0
                }
            }
    }
}
