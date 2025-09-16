import UIKit
import Combine

struct KeyboardHeightObserver {
    let publisher: AnyPublisher<CGFloat, Never>

    init(notificationCenter: NotificationCenter = .default) {
        let willShow = notificationCenter.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification -> CGFloat? in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height
            }

        let willHide = notificationCenter.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat.zero }

        publisher = willShow.merge(with: willHide).eraseToAnyPublisher()
    }
}
