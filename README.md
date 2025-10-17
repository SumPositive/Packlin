# PackList
モチメモ  V3

## StoreKit テスト環境について

- シミュレータでの動作確認は `PackList/Resources/PackListStoreKit.storekit` を利用した StoreKit Test Session で自動化されます。
- `DEBUG` ビルドかつシミュレータ実行時には、課金ボタンを押すと自動で StoreKit Test Session が開始され、ダイアログを表示せずに承認されます。
- 実機で Sandbox テストを行う場合は、これまで通り Sandbox Apple ID でサインインした状態で同じ購入ボタンを実行してください。
