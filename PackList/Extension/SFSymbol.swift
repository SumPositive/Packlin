import SwiftUI
import UIKit

/// 実行中のOSで使えるSF Symbol名を返す
/// iOS26 などで追加されたシンボルを古いOSで使うと空白になるため、
/// 利用できない場合は類似の代替シンボルへフォールバックする
/// - Parameters:
///   - name: 第一候補のシンボル名（新しいOSで追加されたものなど）
///   - fallback: 利用不可時に使う代替シンボル名（全対象OSで使えるもの）
func sfSymbolName(_ name: String, fallback: String) -> String {
    // UIImage(systemName:) は実行中OSにシンボルが無いと nil を返すため、可用性判定に使える
    UIImage(systemName: name) != nil ? name : fallback
}

extension Image {
    /// 利用不可なら代替シンボルへフォールバックして生成する
    init(systemName name: String, fallback: String) {
        self.init(systemName: sfSymbolName(name, fallback: fallback))
    }
}
