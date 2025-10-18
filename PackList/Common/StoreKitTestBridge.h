//
//  StoreKitTestBridge.h
//  PackList
//
//  Swift 側から StoreKitTest のセッション生成を安全に呼び出すための Objective-C ヘッダー。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// StoreKitTest のセッション生成で NSException が発生した場合でもクラッシュさせずに呼び出し結果を返す
/// - Parameters:
///   - configurationURL: バンドル内の StoreKit Configuration ファイルの URL
///   - error: エラー発生時に詳細情報を返すためのポインタ
/// - Returns: 正常に初期化できればセッション（NSObject として返す）、失敗すれば nil
FOUNDATION_EXPORT _Nullable id CreateSKTestSessionSafely(NSURL *configurationURL, NSError **error);

NS_ASSUME_NONNULL_END

