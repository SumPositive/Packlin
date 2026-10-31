//
//  CreditStore.swift
//  PackList
//
//  Created by sumpo on 2025/10/12.
//

import Foundation
import Combine

/// ChatGPT生成で使用するクレジットの残高を管理するObservableObject
/// Keychainへ保存した値を即座に参照しつつ、サーバー側の残高と定期的に同期できるようにする
@MainActor
final class CreditStore: ObservableObject {
    @Published private(set) var credits: Int
    /// azuki-api側でユーザーを識別するためのID。StoreKit購入時にも利用するため
    /// アプリ起動と同時にKeychainへ用意しておく。デバッグ時の即時更新に備えてPublishedで公開する
    @Published private(set) var userId: String
    /// userId が確定しているか。仮の userId（iCloud の元の userId が届くかまだ分からない）の間は false
    /// false の間はクレジットの購入・広告による付与・消費を始めさせない（後で元の userId へ切り替わると、仮の userId の分を使えなくなるため）
    @Published private(set) var isUserIdConfirmed: Bool

    private let keychain: KeychainStorage
    private let keychainBalanceKey = "azuki.credit.balance"
    /// iCloud から userId が後から届いたときの通知の監視
    private var iCloudObserver: NSObjectProtocol?
    /// 旧版で作られた userId を元の userId へ切り替えてよいか、サーバーで確かめている処理（重ねて走らせない）
    private var legacyCheckTask: Task<Void, Never>?

    init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
        // ユーザーIDは起動時に確定させる。広告用IDを別途管理する必要がなくなったため、userIdのみで統一
        // 旧版で作られた userId が iCloud の元の userId と違うときは、サーバーで確かめてから切り替える（checkLegacyUserId 参照）
        let hasLocalCredits = 0 < (keychain.loadInt(forKey: keychainBalanceKey) ?? 0)
        let resolved = AzukiUserIdentifier.loadOrCreate(keychain: keychain, hasLocalCredits: hasLocalCredits)
        self.userId = resolved.userId
        self.isUserIdConfirmed = AzukiUserIdentifier.isConfirmed(keychain: keychain)
        if resolved.didSwitchToICloud {
            // 仮の userId から iCloud の元の userId へ戻ったので、前の userId 向けの残高・トークンは使わない
            keychain.deleteItem(forKey: keychainBalanceKey)
            AzukiApi.shared.clearAuthenticationStateForUserReset()
        }

        if let storedInKeychain = keychain.loadInt(forKey: keychainBalanceKey) {
            // Keychainに保存済みならそのまま採用する
            self.credits = storedInKeychain
        } else {
//            // 旧バージョンのデータ移行：UserDefaultsに値があれば読み出してKeychainへ移す
//            let storedValue = userDefaults.integer(forKey: storageKey)
//            if userDefaults.object(forKey: storageKey) != nil {
//                self.credits = storedValue
//                keychain.saveInt(storedValue, forKey: keychainBalanceKey)
//            } else {
                self.credits = 0
//            }
        }
        observeICloudUserId()
        startLegacyUserIdCheckIfNeeded()
    }

    /// 新端末の初回起動で iCloud の userId がまだ届いておらず仮の userId を発行したあと、
    /// iCloud から元の userId が届いたら、そちらへ切り替える（元のクレジット残高のアカウントへ戻すため）
    /// iCloud に userId が無いと分かったら、仮の userId を正式にして iCloud へ保存する
    private func observeICloudUserId() {
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                self?.handleICloudChange(isInitialSync: reason == NSUbiquitousKeyValueStoreInitialSyncChange)
            }
        }
    }

    private func handleICloudChange(isInitialSync: Bool) {
        switch AzukiUserIdentifier.resolveICloudChange(keychain: keychain,
                                                      isInitialSync: isInitialSync,
                                                      hasLocalCredits: 0 < credits) {
        case .switched(let restoredId):
            switchUserId(to: restoredId)
        case .finalized, .unchanged:
            break
        }
        isUserIdConfirmed = AzukiUserIdentifier.isConfirmed(keychain: keychain)
        startLegacyUserIdCheckIfNeeded()
    }

    /// 前の userId 向けの残高・トークンは捨て、切り替え先の userId で次の通信時にサーバーから取り直す
    private func switchUserId(to newId: String) {
        keychain.deleteItem(forKey: keychainBalanceKey)
        credits = 0
        AzukiApi.shared.clearAuthenticationStateForUserReset()
        userId = newId
    }

    private func startLegacyUserIdCheckIfNeeded() {
        guard legacyCheckTask == nil, AzukiUserIdentifier.legacyCandidate(keychain: keychain) != nil else { return }
        legacyCheckTask = Task { [weak self] in
            await self?.checkLegacyUserId()
            self?.legacyCheckTask = nil
        }
    }

    /// 旧版で作られた userId（iCloud の元の userId と違うもの）に、切り替えると失う状態が無いかをサーバーで確かめる
    /// 残高・広告利用券・公開中のパックがあれば、この端末はいまの userId を使い続ける（公開の取り消しなどは作者の認証が要るため）
    /// どれも無ければ iCloud の元の userId へ切り替える
    /// 通信できなければ判断を保留し、次の起動時や購入・公開などの前にもう一度確かめる（その間は userId を未確定として扱う）
    private func checkLegacyUserId() async {
        guard AzukiUserIdentifier.legacyCandidate(keychain: keychain) != nil else { return }
        let currentId = userId
        if 0 < credits {
            keepLegacyUserId()
            return
        }
        do {
            // 認証トークンもここで取り直すので、続く公開パックの確認より先に呼ぶ
            let status = try await AzukiApi.shared.fetchCreditStatus(userId: currentId)
            guard userId == currentId else { return }
            if 0 < status.balance || 0 < status.adRewardBalance {
                overwrite(credits: status.balance)
                keepLegacyUserId()
                return
            }
            let published = try await AzukiApi.shared.fetchMyPublishedPacks()
            guard userId == currentId else { return }
            if published.isEmpty == false {
                keepLegacyUserId()
                return
            }
            // 失う状態が無いので、元の userId へ切り替える
            if let restoredId = AzukiUserIdentifier.adoptLegacyCandidate(keychain: keychain) {
                switchUserId(to: restoredId)
            }
            isUserIdConfirmed = AzukiUserIdentifier.isConfirmed(keychain: keychain)
        } catch {
            // 判断を保留する
        }
    }

    private func keepLegacyUserId() {
        AzukiUserIdentifier.keepLegacyUserId(keychain: keychain)
        isUserIdConfirmed = AzukiUserIdentifier.isConfirmed(keychain: keychain)
    }

    /// クレジットの購入・広告による付与・消費の前に呼び、userId が確定しているか確かめる
    /// 仮の userId なら iCloud の同期を促して、元の userId が届く（切り替え）か初回同期で無いと分かる（確定）のを少し待つ
    /// - Returns: 確定していれば true。待っても確定しなければ false（呼び出し側は始めずに、再試行できる案内を出す）
    func ensureConfirmedUserId(timeout: TimeInterval = 5) async -> Bool {
        if isUserIdConfirmed { return true }
        let deadline = Date().addingTimeInterval(timeout)
        if AzukiUserIdentifier.legacyCandidate(keychain: keychain) != nil {
            // 旧版で作られた userId は、サーバーで確かめ終わるのを期限まで待つ
            // 期限を過ぎたら未確定として返す（確認は裏で続け、終われば isUserIdConfirmed に反映される）
            startLegacyUserIdCheckIfNeeded()
            while legacyCheckTask != nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            return isUserIdConfirmed
        }
        while Date() < deadline {
            NSUbiquitousKeyValueStore.default.synchronize()
            // 通知を待たずに正式なキーの到着も確かめる（届いていれば切り替える）
            handleICloudChange(isInitialSync: false)
            if isUserIdConfirmed { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return isUserIdConfirmed
    }

    /// クレジットを追加する
    func add(credits amount: Int) {
        // 負値が来ても安全なように上限チェックを行う（0未満なら何もしない）
        if amount < 1 {
            return
        }
        // アプリ仕様：保有枚数が0枚の状態でのみ購入処理が通るため、ここでは単純に加算する
        // （サーバー同期で多めに返ってきた場合も想定し、正の数であればそのまま足し込む）
        credits += amount
        persist()
    }

    /// AdMobのSSVでuserIdが欠けた場合にも、即座に再発行してKeychainへ保存する
    /// - Returns: 確実にKeychainへ保存された最新のuserId
    @discardableResult
    func regenerateUserIdIfNeeded() -> String {
        // Keychain削除後などで空文字になった場合に備え、ここで新規発行する
        if userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let regeneratedId = AzukiUserIdentifier.loadOrCreate(keychain: keychain, hasLocalCredits: 0 < credits).userId
            isUserIdConfirmed = AzukiUserIdentifier.isConfirmed(keychain: keychain)
            // 発行直後にPublished経由でUIへ流すため、メモリ上も更新しておく
            userId = regeneratedId
        }
        return userId
    }

    /// 指定数だけクレジットを消費する
    func consume(credits amount: Int) throws {
        if amount < 1 {
            return
        }
        if credits < amount {
            throw AzukiAPIError.insufficientCredits
        }
        credits -= amount
        persist()
    }

    /// サーバーから取得した残高で上書きしたい場合に使用する
    /// - Parameter amount: サーバーが返した最新残高
    func overwrite(credits amount: Int) {
        if amount < 0 {
            // 負の値が来た場合は安全側として0枚に矯正する
            credits = 0
        } else {
            // 上限を撤廃したため、サーバー値をそのまま反映する
            credits = amount
        }
        persist()
    }

    /// 現在の残高を初期化したい場合用
    func reset() {
        credits = 0
        persist()
    }

    #if DEBUG
    /// Keychainに保存されたユーザーIDとクレジット残高を削除して初期状態に戻す（デバッグ専用）
    func deleteUserIdForDebug() {
        // ここでは再発行せずに純粋な初期状態へ戻す
        AzukiUserIdentifier.delete(keychain: keychain)
        // クレジットも同時にクリアし、Keychainから削除してからメモリ上の値を0にそろえる
        keychain.deleteItem(forKey: keychainBalanceKey)
        credits = 0
        // デバッグでuserIdを空にすると旧ユーザー向けのアクセストークンが残ってしまうため、
        // サーバーの認証エラーを避ける目的でアクセストークンとリフレッシュトークンも破棄する
        AzukiApi.shared.clearAuthenticationStateForUserReset()
        // Keychain にキャッシュされた App Attest 証明書も破棄し、次回購入時に再 Attest させる
        AzukiApi.shared.invalidateDeviceIdentityForDebug()
        // Publishedを通じてUIへ即座に反映させるため空文字を反映
        userId = ""
    }

    /// デバッグ専用: userId を指定値へ切り替える（例: 管理者アカウントへ戻す）。
    /// 残高やトークンは元ユーザー向けの古い値なので、削除時と同様にクリア・再認証させる。
    func setUserIdForDebug(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        AzukiUserIdentifier.set(trimmed, keychain: keychain)
        isUserIdConfirmed = true
        // 直前ユーザーのクレジット・認証状態が混ざらないようにクリアする
        keychain.deleteItem(forKey: keychainBalanceKey)
        credits = 0
        AzukiApi.shared.clearAuthenticationStateForUserReset()
        AzukiApi.shared.invalidateDeviceIdentityForDebug()
        // UIへ即反映
        userId = trimmed
    }
    #endif

    private func persist() {
        // Keychainに書き込み
        keychain.saveInt(credits, forKey: keychainBalanceKey)
    }
}

/// azuki-apiがユーザーを一意に判定するためのIDを管理するヘルパ
private enum AzukiUserIdentifier {
    fileprivate static let storageKey = "azuki.api.userId"

    /// 仮の userId であることの印（Keychain）。値があれば、まだ iCloud の正式なキーへ保存していない仮の userId
    /// 新端末の初回起動で iCloud の値が届く前に発行したもの。後から iCloud の元の userId が届けばそちらへ切り替える
    /// 仮の userId のうちはクレジットの購入・付与・消費や公開を始めさせないので、仮の userId が残高を持つことはない
    fileprivate static let provisionalKey = "azuki.api.userId.provisional"
    private static let unconfirmedValue = "1"
    /// 仮の userId を iCloud に控えておくキー（正式なキー storageKey とは別）
    /// 正式なキーへ書くと、同期が遅れているだけの元の userId を上書きして失うため、こちらへ控える
    /// 端末故障などで仮のまま失っても、同じ Apple ID の新端末で復元できるようにする
    fileprivate static let provisionalBackupKey = "azuki.api.userId.provisionalBackup"
    /// 旧版で作られた userId から切り替える候補（Keychain）。値があれば、サーバーで切り替えてよいか確かめるまで userId を未確定として扱う
    private static let legacyCandidateKey = "azuki.api.userId.legacyCandidate"
    /// 旧版で作られた userId を使い続けると決めたときの候補（Keychain）。同じ候補なら次から確かめない
    private static let legacyKeptKey = "azuki.api.userId.legacyKept"

    /// userId を解決する。優先順位は以下（端末故障後も同じ Apple ID で復元できるようにする）:
    ///   1. Keychain にあればそれを採用（現役の残高・トークンとの整合を最優先）。
    ///      このとき iCloud 側が未設定なら iCloud にも写して、既存ユーザーも次回以降復元可能にする。
    ///      iCloud に別の userId があれば、切り替え候補として控える（markLegacyCandidate）。
    ///      旧版は iCloud の同期前に新しい userId を発行して Keychain を優先していたため、元の userId が後から届いても使えずにいた端末を救う。
    ///      ただし、いまの userId に残高・公開中のパックなどがあれば切り替えない（iCloud 対応より前から複数端末で別々のアカウントを使っていた場合）。
    ///      その確認はサーバーが要るので、ここでは切り替えず、CreditStore.checkLegacyUserId で行う。
    ///      ただし仮の userId なら iCloud の正式なキーへは写さない。正式なキーに別の userId があれば、そちらが元のアカウントなので切り替える。
    ///   2. Keychain に無く iCloud の正式なキーにあれば、それを採用して Keychain へ書き戻す（機種変更後の復元）。
    ///   3. 正式なキーに無く控えのキーにあれば、それを仮の userId として採用する（仮のまま端末を替えた場合）。
    ///   4. どれにも無ければ新規 UUID を生成し、仮の userId として Keychain と iCloud の控えのキーに保存する。
    ///      iCloud の同期が初回起動に間に合っていないだけかもしれないので、正式なキーには書かない。
    /// 仮の userId を正式にするのは、iCloud の初回同期の通知で正式なキーが無いと確かめられたときだけ（resolveICloudChange）。
    /// 起動回数や経過時間では判断しない（同期が遅れているだけのこともあるため）。
    /// - Parameters:
    ///   - keychain: アプリ再インストール後も維持したい本来の保存先
    ///   - iCloud: 端末をまたいで userId を引き継ぐための iCloud Key-Value Store
    ///   - hasLocalCredits: この端末に残高があるか（あれば確定済みの userId を切り替え候補にしない）
    /// - Returns: APIへ渡すuserIdと、iCloud の userId へ切り替えたか
    static func loadOrCreate(keychain: KeychainStorage,
                             iCloud: ICloudKeyValueStore = ICloudKeyValueStore(),
                             hasLocalCredits: Bool = false) -> (userId: String, didSwitchToICloud: Bool) {
        // 1. Keychain 優先
        if let storedInKeychain = keychain.loadString(forKey: storageKey), storedInKeychain.isEmpty == false {
            let storedInICloud = iCloud.loadString(forKey: storageKey)
            if isUnconfirmed(keychain: keychain) {
                if let storedInICloud {
                    if storedInICloud != storedInKeychain {
                        // 前回の起動後に iCloud の元の userId が届いていた → 元のアカウントへ戻す
                        adopt(storedInICloud, keychain: keychain)
                        return (storedInICloud, true)
                    }
                    // 正式なキーと同じなら正式にする（印だけ外す）
                    keychain.deleteItem(forKey: provisionalKey)
                    return (storedInKeychain, false)
                }
                // まだ判断できないので仮のまま使う（正式なキーには書かない）
                backUpProvisional(storedInKeychain, iCloud: iCloud)
                return (storedInKeychain, false)
            }
            // 旧版で作られた userId が iCloud の元の userId と違う → 切り替えてよいかは後でサーバーで確かめる
            markLegacyCandidate(current: storedInKeychain, storedInICloud: storedInICloud,
                                keychain: keychain, hasLocalCredits: hasLocalCredits)
            // 既存ユーザーの移行: iCloud 未設定なら写しておく（次回以降の復元に備える）
            if storedInICloud == nil {
                iCloud.saveString(storedInKeychain, forKey: storageKey)
            }
            return (storedInKeychain, false)
        }
        // 2. iCloud からの復元（機種変更・端末故障後の新端末など）
        if let storedInICloud = iCloud.loadString(forKey: storageKey), storedInICloud.isEmpty == false {
            keychain.saveString(storedInICloud, forKey: storageKey)
            return (storedInICloud, false)
        }
        // 3. 仮のまま控えていた userId の復元（正式なキーが後から届けば切り替えられるよう、仮のまま扱う）
        if let backedUp = iCloud.loadString(forKey: provisionalBackupKey) {
            keychain.saveString(backedUp, forKey: storageKey)
            keychain.saveString(unconfirmedValue, forKey: provisionalKey)
            return (backedUp, false)
        }
        // 4. 新規発行 → 仮の userId として Keychain と控えのキーに保存（正式なキーにはまだ書かない）
        let newId = UUID().uuidString.lowercased()
        keychain.saveString(newId, forKey: storageKey)
        keychain.saveString(unconfirmedValue, forKey: provisionalKey)
        backUpProvisional(newId, iCloud: iCloud)
        return (newId, false)
    }

    enum ProvisionalResolution {
        /// iCloud の元の userId へ切り替えた
        case switched(String)
        /// iCloud に userId が無いと分かり、仮の userId を正式にした
        case finalized
        /// 何もしなかった（同じ userId・残高がある・まだ判断できない）
        case unchanged
    }

    /// iCloud の変更通知を受けたときに、iCloud の元の userId へ切り替えるか、仮の userId を正式にするかを決める
    /// - 仮の userId：元の userId が届けば切り替え、初回同期でも無ければ正式にする
    /// - 確定済みの userId（旧版で作られたもの）：元の userId が別に届けば切り替え候補として控える（loadOrCreate と同じ判断）
    /// - Parameters:
    ///   - isInitialSync: 初回同期の通知か。初回同期を終えても正式なキーに無いときだけ、本当に無いとみなして正式にする
    ///   - hasLocalCredits: この端末に残高があるか
    static func resolveICloudChange(keychain: KeychainStorage,
                                    iCloud: ICloudKeyValueStore = ICloudKeyValueStore(),
                                    isInitialSync: Bool,
                                    hasLocalCredits: Bool) -> ProvisionalResolution {
        guard let current = keychain.loadString(forKey: storageKey), current.isEmpty == false else {
            return .unchanged
        }
        guard isUnconfirmed(keychain: keychain) else {
            markLegacyCandidate(current: current, storedInICloud: iCloud.loadString(forKey: storageKey),
                                keychain: keychain, hasLocalCredits: hasLocalCredits)
            return .unchanged
        }
        if let storedInICloud = iCloud.loadString(forKey: storageKey) {
            if storedInICloud != current {
                // 仮の userId は残高を持たない（購入などを止めている）ので、いつも切り替える
                adopt(storedInICloud, keychain: keychain)
                return .switched(storedInICloud)
            }
            // 同じ値なら既に保存済み（印だけ外す）
            keychain.deleteItem(forKey: provisionalKey)
            return .finalized
        }
        if isInitialSync {
            // 初回同期が終わっても正式なキーが無い → 元の userId は無いので、仮の userId を正式にする
            iCloud.saveString(current, forKey: storageKey)
            keychain.deleteItem(forKey: provisionalKey)
            return .finalized
        }
        return .unchanged
    }

    /// まだ確定していない仮の userId か
    private static func isUnconfirmed(keychain: KeychainStorage) -> Bool {
        keychain.loadString(forKey: provisionalKey) == unconfirmedValue
    }

    /// userId が確定しているか（仮の userId でなく、旧版の userId の切り替え確認待ちでもない）
    static func isConfirmed(keychain: KeychainStorage) -> Bool {
        !isUnconfirmed(keychain: keychain) && legacyCandidate(keychain: keychain) == nil
    }

    /// 旧版で作られた userId から切り替える候補（iCloud の元の userId）。サーバーでの確認待ちのときだけ値がある
    static func legacyCandidate(keychain: KeychainStorage) -> String? {
        keychain.loadString(forKey: legacyCandidateKey)
    }

    /// 確定済みの userId が iCloud の userId と違えば、切り替え候補として控える
    /// この端末に残高があるとき、または同じ候補で使い続けると決めたあとは控えない
    private static func markLegacyCandidate(current: String,
                                            storedInICloud: String?,
                                            keychain: KeychainStorage,
                                            hasLocalCredits: Bool) {
        guard let storedInICloud, storedInICloud != current,
              !hasLocalCredits,
              keychain.loadString(forKey: legacyKeptKey) != storedInICloud else {
            keychain.deleteItem(forKey: legacyCandidateKey)
            return
        }
        keychain.saveString(storedInICloud, forKey: legacyCandidateKey)
    }

    /// サーバーで確かめて失う状態が無かったので、切り替え候補の userId を採用する
    static func adoptLegacyCandidate(keychain: KeychainStorage) -> String? {
        guard let candidate = legacyCandidate(keychain: keychain) else { return nil }
        adopt(candidate, keychain: keychain)
        return candidate
    }

    /// いまの userId を使い続けると決めた（同じ候補では、次から確かめない）
    static func keepLegacyUserId(keychain: KeychainStorage) {
        guard let candidate = legacyCandidate(keychain: keychain) else { return }
        keychain.saveString(candidate, forKey: legacyKeptKey)
        keychain.deleteItem(forKey: legacyCandidateKey)
    }

    /// iCloud の userId を採用する（それまでの userId を捨てる）
    private static func adopt(_ id: String, keychain: KeychainStorage) {
        keychain.saveString(id, forKey: storageKey)
        keychain.deleteItem(forKey: provisionalKey)
        keychain.deleteItem(forKey: legacyCandidateKey)
    }

    /// 仮の userId を iCloud の控えのキーへ保存する（既に控えがあれば上書きしない。別端末の仮の userId を消さないため）
    private static func backUpProvisional(_ id: String, iCloud: ICloudKeyValueStore) {
        if iCloud.loadString(forKey: provisionalBackupKey) == nil {
            iCloud.saveString(id, forKey: provisionalBackupKey)
        }
    }

    #if DEBUG
    /// 保存されたユーザーIDを削除する（デバッグ専用）。
    /// Keychain だけ消しても iCloud から復元されてしまうため、iCloud 側も削除する。
    /// - Parameters:
    ///   - keychain: 削除先となるKeychain
    ///   - iCloud: 削除先となる iCloud Key-Value Store
    static func delete(keychain: KeychainStorage,
                       iCloud: ICloudKeyValueStore = ICloudKeyValueStore()) {
        // SecItemDeleteに任せ、存在しない場合でもエラーとしない
        keychain.deleteItem(forKey: storageKey)
        keychain.deleteItem(forKey: provisionalKey)
        keychain.deleteItem(forKey: legacyCandidateKey)
        keychain.deleteItem(forKey: legacyKeptKey)
        iCloud.removeValue(forKey: storageKey)
        iCloud.removeValue(forKey: provisionalBackupKey)
    }

    /// 指定した userId を強制的に設定する（デバッグ専用）。
    /// 管理者アカウント（サンプル公開の運用者）へ戻す等に使う。Keychain と iCloud の両方へ書く。
    /// - Parameters:
    ///   - id: 設定したい userId
    ///   - keychain: 保存先Keychain
    ///   - iCloud: 保存先 iCloud Key-Value Store
    static func set(_ id: String,
                    keychain: KeychainStorage,
                    iCloud: ICloudKeyValueStore = ICloudKeyValueStore()) {
        keychain.saveString(id, forKey: storageKey)
        keychain.deleteItem(forKey: provisionalKey)
        keychain.deleteItem(forKey: legacyCandidateKey)
        iCloud.saveString(id, forKey: storageKey)
    }
    #endif

}
