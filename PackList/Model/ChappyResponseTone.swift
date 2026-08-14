//  チャッピー応答トーン
//  会話の文体選択と保存値を定義する
//

import Foundation

enum ChappyResponseTone: String, CaseIterable, Identifiable {
    case concise
    case gentle
    case direct
    case fun

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .concise:
            return String(localized: "chappy.tone.concise", defaultValue: "簡潔")
        case .gentle:
            return String(localized: "chappy.tone.gentle", defaultValue: "やさしい")
        case .direct:
            return String(localized: "chappy.tone.direct", defaultValue: "率直")
        case .fun:
            return String(localized: "chappy.tone.fun", defaultValue: "楽しい")
        }
    }
}
