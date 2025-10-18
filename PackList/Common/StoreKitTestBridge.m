//
//  StoreKitTestBridge.m
//  PackList
//
//  StoreKitTest の SKTestSession 初期化時に発生する NSException を握りつぶして
//  Swift 側へ NSError として伝えるための Objective-C 実装。
//

#import "StoreKitTestBridge.h"

#if __has_include(<StoreKitTest/StoreKitTest.h>)
#import <StoreKitTest/StoreKitTest.h>
#define HAS_STOREKITTEST 1
#else
#define HAS_STOREKITTEST 0
#endif

id _Nullable CreateSKTestSessionSafely(NSURL *configurationURL, NSError **error) {
#if HAS_STOREKITTEST
    @try {
        // initWithConfigurationFileURL:error: は Swift 側の `SKTestSession(contentsOf:)` に対応する Objective-C API
        // ここで発生する NSException を捕捉することで SIGABRT を防ぐ
        return [[SKTestSession alloc] initWithConfigurationFileURL:configurationURL error:error];
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSDictionary *info = @{NSLocalizedDescriptionKey: exception.reason ?: @"StoreKitTest セッション初期化で例外が発生しました。"};
            *error = [NSError errorWithDomain:@"StoreKitTestBridge" code:-1 userInfo:info];
        }
        return nil;
    }
#else
    if (error != NULL) {
        NSDictionary *info = @{NSLocalizedDescriptionKey: @"StoreKitTest.framework がリンクされていないためセッションを生成できません。"};
        *error = [NSError errorWithDomain:@"StoreKitTestBridge" code:-2 userInfo:info];
    }
    return nil;
#endif
}

