# PackList
モチメモ  V3

## StoreKit テスト環境について

- シミュレータでの動作確認は `PackList/Resources/PackListStoreKit.storekit` を利用した StoreKit Test Session で自動化されます。
- `DEBUG` ビルドかつシミュレータ実行時には、課金ボタンを押すと自動で StoreKit Test Session が開始され、ダイアログを表示せずに承認されます。
- iOS 16 以降のシミュレータでは Swift Concurrency 対応の `StoreKitTestSession` を利用し、非同期のトランザクションクリアを await してから購入フローに進みます。iOS 14〜15 のシミュレータでは従来通り `SKTestSession` にフォールバックします。
- 実機で Sandbox テストを行う場合は、これまで通り Sandbox Apple ID でサインインした状態で同じ購入ボタンを実行してください。
- Xcode プロジェクト側では `StoreKitTest.framework` を弱リンク（Optional）として追加しているため、DEBUG + シミュレータ環境であれば追加設定なしに `StoreKitTest` モジュールが解決されます。実機ビルドでは弱リンクにより取り除かれるため、配布バイナリへ影響はありません。
