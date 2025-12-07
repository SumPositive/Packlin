# モチメモ/Packlin V3

## Codex

- V2 Objective-C から Swift/SwiftUI 変換に Codex を利用したのを手始めに Codex を徹底利用する方針とし、System prompt や指示方法などのノウハウを蓄積している


## StoreKit 購入テスト環境について

- シミュレータ向けの StoreKit Test Session 自動化は廃止しました。課金フローの検証は実機 + Sandbox Apple ID で行ってください
- 実機テストでは、端末の App Store に Sandbox Apple ID でサインインした状態でアプリを起動し、AI利用回数券の購入ボタンを操作します
- StoreKit 関連の追加フレームワークやテスト用 `.storekit` ファイルは不要になったため、Xcode プロジェクトにも特別な設定はありません
- TestFlightで配布されたアプリはRELEASEモードですが、StoreKitは購入テストモードで動作しますので課金はされません
