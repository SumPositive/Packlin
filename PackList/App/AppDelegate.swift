import Foundation
import SwiftUI
import UIKit
import FirebaseCore

/// アプリ全体の初期化とFirebaseの構成を担当するAppDelegate
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // 実行環境を取得してFirebase初期化の可否を判定する
        let environment = ProcessInfo.processInfo.environment
        let processArguments = ProcessInfo.processInfo.arguments
        let isFirebaseAllowed = AppMain.shouldEnableFirebase(environment: environment, processArguments: processArguments)
        if isFirebaseAllowed && FirebaseApp.app() == nil {
            // 必要な環境でのみFirebaseAppを構成する
            FirebaseApp.configure()
        }

        return true
    }
}
