# PackList
モチメモ  V3

## StoreKit 購入テスト環境について

- シミュレータ向けの StoreKit Test Session 自動化は廃止しました。課金フローの検証は実機 + Sandbox Apple ID で行ってください
- 実機テストでは、端末の App Store に Sandbox Apple ID でサインインした状態でアプリを起動し、AI利用回数券の購入ボタンを操作します
- StoreKit 関連の追加フレームワークやテスト用 `.storekit` ファイルは不要になったため、Xcode プロジェクトにも特別な設定はありません
・TestFlightで配布されたアプリはRELEASEモードですが、StoreKitは購入テストモードで動作しますので課金はされません
