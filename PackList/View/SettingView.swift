//  設定画面
//  表示設定、バックアップ、インポート、アプリ情報をまとめる
//

import SwiftUI
import SafariServices
import SwiftData
import UniformTypeIdentifiers
import Foundation
import StoreKit


let SettingView_HEIGHT: CGFloat = 710.0 // シート表示時の高さ指定

/// 新規追加する位置
enum InsertionPosition: String, CaseIterable, Identifiable, Codable {
    // 選択肢
    case head // 先頭
    case tail // 末尾
    // 初期値
    static let `default`: InsertionPosition = DEF_insertionPosition
    
    var id: String { rawValue }
    
    var localizedKey: LocalizedStringKey {
        switch self {
            case .head:
                return "top"
            case .tail:
                return "bottom"
        }
    }
    
    var iconSFname: String {
        switch self {
            case .head:
                return "text.line.first.and.arrowtriangle.forward"
            case .tail:
                return "text.line.last.and.arrowtriangle.forward"
        }
    }
}

/// 設定画面：以前はPopup表示だったが、PackEditViewと揃えてシート表示に対応
struct SettingView: View {

    @EnvironmentObject private var creditStore: CreditStore
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @State private var showDebugUserIdAlert = false
    // 管理者アカウント等へ userId を戻すための入力
    @State private var debugUserIdInput = ""
    @State private var showDebugSetUserIdAlert = false
    #endif

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        SettingSection {
                            // カスタム設定
                            CustomSetView()
                        }
                        
                        SettingSection {
                            // 全パックを書き出す（バックアップ）
                            BackupExportView()
                            Divider()
                            // 保存パックを読み込む
                            ShareView()
                        }

                        SettingSection {
                            // 作者ニックネーム（公開されます）
                            AuthorNicknameView()
                        }

                        SettingSection {
                            // 情報
                            InformationView()
                        }
                        
                        SettingSection {
                            // 応援・寄付
                            DonationView()
                        }

                        // Version - SupportID
                        if let versionLineText {
                            VStack(spacing: 10) {
                                HStack {
                                    Spacer()
                                    // 画面最下部でアプリバージョンとサポート用ID(userIdの先頭8桁)を一緒に表示する
                                    Text(versionLineText)
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                #if DEBUG
                                Button {
                                    // デバッグ中にKeychainへ保存されたSupportID(userId)を削除し、純粋な初期状態へ戻す
                                    creditStore.deleteUserIdForDebug()
                                    showDebugUserIdAlert = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .symbolRenderingMode(.hierarchical)
                                        Text(String(localized: "delete.user.id.ai.tickets"))
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red.opacity(0.7))
                                .controlSize(.small)
                                .padding(.bottom, 4)

                                // デバッグ: userId を指定値へ切り替える（管理者アカウントへ戻す等）
                                HStack(spacing: 6) {
                                    TextField("user.id.debug.placeholder", text: $debugUserIdInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.footnote.monospaced())
                                        .textFieldStyle(.roundedBorder)
                                    Button {
                                        creditStore.setUserIdForDebug(debugUserIdInput)
                                        debugUserIdInput = ""
                                        showDebugSetUserIdAlert = true
                                    } label: {
                                        Text("user.id.debug.set")
                                            .font(.footnote.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(debugUserIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                .padding(.bottom, 4)
                                #endif
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // スクロール位置表示は全画面で出さない
                .scrollIndicators(.hidden)
                // シートでは端末サイズに追従させるため、幅と高さの固定は行わない
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, -20)
            }
            .navigationTitle(Text("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            #if DEBUG
            .alert(String(localized: "user.id.ai.tickets.deleted"), isPresented: $showDebugUserIdAlert) {
                Button(role: .cancel) {
                    // 閉じるだけで処理は完了。画面はPublished経由で更新される
                } label: {
                    Text("OK")
                }
            } message: {
                // 次回利用時に自動で再発行されることを知らせつつ、クレジット初期化も明示する
                Text(String(localized: "user.id.recreated.when.needed"))
            }
            .alert(String(localized: "user.id.debug.set.done"), isPresented: $showDebugSetUserIdAlert) {
                Button(role: .cancel) { } label: { Text("OK") }
            } message: {
                Text(String(localized: "user.id.debug.set.done.message"))
            }
            #endif
        }
    }
    
    /// 作者ニックネーム（公開されます）の編集。変更はサーバーへ反映し、過去の公開パックにも適用される
    private struct AuthorNicknameView: View {
        @EnvironmentObject private var creditStore: CreditStore
        @AppStorage(AppStorageKey.authorNickname) private var authorNickname: String = ""
        @AppStorage(AppStorageKey.authorNicknameConfigured) private var authorNicknameConfigured: Bool = false
        @State private var draft: String = ""
        @State private var isSaving = false
        @State private var statusMessage: String?
        @FocusState private var focused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("publish.nickname.title")
                    .font(.body.weight(.semibold))

                HStack(spacing: 8) {
                    TextField(text: $draft) {
                        Text("publish.nickname.placeholder")
                    }
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("publish.nickname.save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("publish.nickname.footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { draft = authorNickname }
        }

        @MainActor
        private func save() async {
            if isSaving { return }
            focused = false
            isSaving = true
            defer { isSaving = false }
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let userId = creditStore.regenerateUserIdIfNeeded()
                // 認証必須エンドポイントのため、トークン未取得ならまず credit/check で発行する
                if AzukiApi.shared.hasValidAccessToken() == false {
                    _ = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
                }
                let saved = try await AzukiApi.shared.updateNickname(userId: userId, nickname: trimmed)
                authorNickname = saved
                authorNicknameConfigured = true
                draft = saved
                statusMessage = nil
            } catch let apiError as AzukiAPIError {
                statusMessage = apiError.errorDescription
            } catch {
                statusMessage = String(localized: "network.seems.down.please.try.again")
            }
        }
    }

    private struct SettingSection<Content: View>: View {
        @Environment(\.colorScheme) private var colorScheme
        private let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        }

        private var backgroundColor: Color {
            if colorScheme == .dark {
                return Color(uiColor: .systemGray3)
            } else {
                return Color(uiColor: .systemGray6)
            }
        }

        private var shadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.65) : Color.black.opacity(0.12)
        }
    }
    
    /// カスタムSafariシート
    struct SafariView: UIViewControllerRepresentable {
        let url: URL
        func makeUIViewController(context: Context) -> SFSafariViewController {
            return SFSafariViewController(url: url)
        }
        func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    }

    private var versionLineText: String? {
        // Info.plistからアプリバージョンとビルド番号を合成する
        guard let versionText else {
            return nil
        }
        // サポート用IDが取得できなければVersionだけを表示する
        guard let supportId = supportUserId else {
            return "Version \(versionText)"
        }
        // ビルド番号付きバージョンとサポートIDの両方を表示する
        return "Version \(versionText).\(supportId)"
    }

    private var versionText: String? {
        // アプリの表示用バージョンとビルド番号をドット区切りで繋ぐ
        guard let appVersion else {
            return nil
        }
        // CFBundleVersionが取得できた場合のみ末尾に連結する
        guard let buildVersion, buildVersion.isEmpty == false else {
            return appVersion
        }
        return "\(appVersion).\(buildVersion)"
    }

    private var appVersion: String? {
        // ユーザー向けに表示するため短縮バージョン文字列を参照する
        guard let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return bundleVersion
    }

    private var buildVersion: String? {
        // ビルド番号をInfo.plistから取得し、存在しない場合はnilを返す
        guard let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return nil
        }
        return bundleBuild
    }

    private var supportUserId: String? {
        // userIdは通信周りで生成されるため、空文字の場合は表示しない
        let rawId = creditStore.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawId.isEmpty {
            return nil
        }
        // userIdはKeychainに保存されるUUIDでプレースホルダー値は存在しないため、そのまま表示対象とする
        // 先頭8文字だけを抜き出してサポート用識別子に使う
        return abbreviatedSupportId(from: rawId)
    }

    /// SupportIDとして短縮したuserIdの先頭8文字を返す
    /// - Parameter rawId: Keychainなどに保存された元のuserId
    /// - Returns: 8文字に短縮したSupportID（元の長さが不足する場合はそのまま返す）
    private func abbreviatedSupportId(from rawId: String) -> String {
        if rawId.count < 8 {
            return rawId
        }
        let endIndex = rawId.index(rawId.startIndex, offsetBy: 8)
        return String(rawId[rawId.startIndex..<endIndex])
    }

    /// アプリの取扱説明
    struct InformationView: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
        @State private var showSafari = false

        private var guideURL: URL? {
            let urlString = String(localized: "info.url")
            guard var components = URLComponents(string: urlString) else {
                return URL(string: urlString)
            }
            var queryItems = components.queryItems ?? []
            // 既存URLに同名パラメータがある場合はアプリ側の現在値で上書きする
            queryItems.removeAll { $0.name == "fontScale" }
            // docs.azukid.com の取扱説明へアプリ設定の文字サイズを渡す
            queryItems.append(URLQueryItem(name: "fontScale", value: guideFontScaleParameter))
            components.queryItems = queryItems
            return components.url
        }

        private var guideFontScaleParameter: String {
            switch fontScale {
            case .system:
                return guideFontScaleParameter(for: dynamicTypeSize)
            case .standard, .large, .xLarge:
                return fontScale.rawValue
            }
        }

        private func guideFontScaleParameter(for size: DynamicTypeSize) -> String {
            if size <= .xLarge {
                return FontScale.standard.rawValue
            }
            if size <= .xxxLarge {
                return FontScale.large.rawValue
            }
            return FontScale.xLarge.rawValue
        }
        
        var body: some View {
            Button(action: {
                // SafariでURLを表示する
                showSafari = true
                GALogger.log(.feature_use(name: "user_guide", source: "settings", detail: "open"))
            }) {
                Label {
                    Text("about.how.use")
                        .font(.body.weight(.bold))
                        .foregroundColor(.accentColor)
                } icon: {
                    Image(systemName: "info.circle")
                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSafari) {
                if let url = guideURL {
                    SafariView(url: url)
                } else {
                    Text("can.t.show.info")
                }
            }
        }
    }

    /// 全パックを1つのバックアップファイルに書き出す
    struct BackupExportView: View {
        @Environment(\.modelContext) private var modelContext
        @State private var shareURL: URL?
        @State private var isPresentingShare = false
        @State private var errorAlert: String?
        @State private var isExporting = false

        var body: some View {
            Button(action: startExport) {
                Label {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(isExporting ? "exporting" : "export.all.packs.backup"))
                            .font(.body.weight(.bold))
                            .foregroundColor(isExporting ? .secondary : .accentColor)
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .sheet(isPresented: $isPresentingShare, onDismiss: cleanupShareResource) {
                if let shareURL {
                    ActivityView(activityItems: [shareURL])
                        .ignoresSafeArea()
                }
            }
            .alert(String(localized: "export.failed"), isPresented: Binding(
                get: { errorAlert != nil },
                set: { if !$0 { errorAlert = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorAlert ?? "")
            }
        }

        private func startExport() {
            guard !isExporting else { return }
            isExporting = true
            // バックアップ書き出しの利用頻度を集計する
            GALogger.log(.feature_use(name: "backup_export", source: "settings", detail: "start"))

            Task {
                do {
                    // modelContext はメインアクターのため、ここで fetch する
                    let descriptor = FetchDescriptor<M1Pack>(sortBy: [SortDescriptor(\.order)])
                    let packs = try modelContext.fetch(descriptor)
                    let backup = BackupJsonDTO(
                        productName: PACK_JSON_DTO_PRODUCT_NAME,
                        copyright: PACK_JSON_DTO_COPYRIGHT,
                        version: PACK_JSON_DTO_VERSION,
                        exportedAt: Date(),
                        packs: packs.map { $0.backupRepresentation() }
                    )

                    // JSON エンコードとファイル書き込みをバックグラウンドで実行
                    let fileURL = try await Task.detached(priority: .userInitiated) {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        let data = try encoder.encode(backup)

                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyyMMdd_HHmmss"
                        let dateStr = formatter.string(from: Date())
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("Backup_\(dateStr)")
                            .appendingPathExtension(PACK_FILE_EXTENSION)
                        try data.write(to: url, options: [.atomic])
                        return url
                    }.value

                    // メインアクターでシートを表示
                    shareURL = fileURL
                    isPresentingShare = true
                } catch {
                    // バックアップ書き出し失敗をAnalyticsへ送り、保存/共有問題の分析に使う
                    logError(error, domain: "settings_backup_export", message: "バックアップ書き出し失敗")
                    errorAlert = error.localizedDescription
                }
                isExporting = false
            }
        }

        private func cleanupShareResource() {
            guard let shareURL else {
                shareURL = nil
                return
            }
            try? FileManager.default.removeItem(at: shareURL)
            self.shareURL = nil
        }
    }

    /// *.packlin / *.packlinbackup 読み込み
    struct ShareView: View {
        @Environment(\.modelContext) private var modelContext

        /// 設定画面で指定された挿入位置を共有インポートにも適用するためのAppStorage
        @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
        @State private var isPresentingImporter = false
        @State private var importAlert: ImportAlert?

        var body: some View {
            Button(action: {
                isPresentingImporter = true
                GALogger.log(.feature_use(name: "pack_import", source: "settings", detail: "open"))
            }) {
                Label {
                    Text("import.pack.overwrites.existing")
                        .font(.body.weight(.bold))
                        .foregroundColor(.accentColor)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $isPresentingImporter,
                allowedContentTypes: [PACK_FILE_UTTYPE],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        importAlert = try importFile(from: url)
                    } catch {
                        // 取り込み失敗をAnalyticsへ送り、ファイル形式や読込問題の分析に使う
                        logError(error, domain: "settings_import", message: "取り込み失敗")
                        importAlert = .failure(message: error.localizedDescription)
                    }
                case .failure(let error):
                    // ファイル選択失敗をAnalyticsへ送り、DocumentPickerまわりの問題分析に使う
                    logError(error, domain: "settings_file_importer", message: "ファイル選択失敗")
                    importAlert = .failure(message: error.localizedDescription)
                }
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }

        // MARK: - ファイル読み込みエントリポイント

        /// JSONの最上位キーでディスパッチして単体またはバックアップとして読み込む
        /// - `packs` キーを持つ → BackupJsonDTO（全パックバックアップ）
        /// - `groups` キーを持つ → PackJsonDTO（単体パック）
        /// - いずれも持たない → フォーマットエラー
        private func importFile(from url: URL) throws -> ImportAlert {
            let data = try readData(from: url)
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ImportError.invalidFormat
            }
            if root["packs"] != nil {
                return try importBackup(data: data)
            } else if root["groups"] != nil {
                return try importSinglePack(data: data)
            } else {
                throw ImportError.invalidFormat
            }
        }

        /// NSFileCoordinator 経由でファイルデータを読み出す
        private func readData(from url: URL) throws -> Data {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing { url.stopAccessingSecurityScopedResource() }
            }
            let fileManager = FileManager.default
            let temporaryURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)
            defer { try? fileManager.removeItem(at: temporaryURL) }

            var coordinatorError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readingURL in
                do {
                    if fileManager.fileExists(atPath: temporaryURL.path) {
                        try fileManager.removeItem(at: temporaryURL)
                    }
                    try fileManager.copyItem(at: readingURL, to: temporaryURL)
                } catch {
                    copyError = error
                }
            }
            if let coordinatorError { throw coordinatorError }
            if let copyError { throw copyError }
            return try Data(contentsOf: temporaryURL)
        }

        // MARK: - 単体パック (.packlin)

        /// 単体パック（.packlin）を取り込む
        ///
        /// 取り込み手順:
        ///   1. JSON をデコードして `PackJsonDTO` 化
        ///   2. ヘッダー（ProductName/Copyright/Version）の整合性を検証
        ///   3. 既存パック一覧を取得（ID または name で照合するため）
        ///   4. Undo グルーピング開始（取り込み全体を1アクションとして Undo できるようにする）
        ///   5. upsert: 既存と一致すれば上書き、なければ新規挿入
        ///   6. defer で Undo グルーピング終了 + 即時 save
        ///
        /// - Important: defer 内の save は Fix 2 で追加した堅牢化措置。
        ///   インポート完了直後にユーザーがアプリを切った場合でも、
        ///   取り込んだパックが SQLite へ確実に書き込まれるようにする。
        private func importSinglePack(data: Data) throws -> ImportAlert {
            let dto = try JSONDecoder().decode(PackJsonDTO.self, from: data)
            try validateHeader(productName: dto.productName, copyright: dto.copyright, version: dto.version)

            // 既存パック取得失敗は取り込み失敗として呼び出し元でAnalytics送信する
            var existingPacks = try modelContext.fetch(FetchDescriptor<M1Pack>())
            // 取り込み全体を 1 つの Undo 操作にまとめる
            modelContext.undoManager?.groupingBegin()
            defer {
                // 関数を抜けるときに Undo グループを閉じる。
                // 通常 return / throw のどちらでも必ず実行される。
                modelContext.undoManager?.groupingEnd()
                // === Fix 2: 取り込み直後の永続化 ===
                // SwiftData の通常 save タイミング（背景遷移時）を待たず、
                // インポート直後にクラッシュしても変更が消えないよう即時に書き出す。
                persistAfterImport(domain: "import_single_save")
            }

            let (pack, wasOverwritten) = upsertPack(dto: dto, existingPacks: &existingPacks)
            return .success(packName: pack.name, wasOverwritten: wasOverwritten)
        }

        // MARK: - 全パックバックアップ (.packlinbackup)

        /// 全パックバックアップ（.packlinbackup 相当）を取り込む
        ///
        /// 取り込み手順は importSinglePack と同じだが、複数パックをループで処理する。
        ///
        /// - Important: defer 内の save は Fix 2 で追加した堅牢化措置。
        ///   特にバックアップ取り込みは「機種変更直後」「データ復元」など
        ///   ユーザーにとって最重要のシナリオで使われるため、即時 save の効果が大きい。
        private func importBackup(data: Data) throws -> ImportAlert {
            let backup = try JSONDecoder().decode(BackupJsonDTO.self, from: data)
            try validateHeader(productName: backup.productName, copyright: backup.copyright, version: backup.version)

            // 既存パック取得失敗は取り込み失敗として呼び出し元でAnalytics送信する
            var existingPacks = try modelContext.fetch(FetchDescriptor<M1Pack>())
            // バックアップ全件の取り込みを 1 つの Undo 操作にまとめる
            modelContext.undoManager?.groupingBegin()
            defer {
                modelContext.undoManager?.groupingEnd()
                // === Fix 2: 取り込み直後の永続化 ===
                // バックアップは件数が多くなる傾向があるが、ループ完了後にまとめて
                // 1 度 save する。SwiftData はトランザクションを内部で扱うので
                // 個別 save より効率的。
                persistAfterImport(domain: "import_backup_save")
            }

            var added = 0, overwritten = 0
            for dto in backup.packs {
                let (_, wasOverwritten) = upsertPack(dto: dto, existingPacks: &existingPacks)
                if wasOverwritten { overwritten += 1 } else { added += 1 }
            }
            return .successBatch(added: added, overwritten: overwritten)
        }

        /// インポート完了直後の永続化ヘルパー
        ///
        /// - 呼び出しタイミング: Undo グルーピング終了（`groupingEnd()`）の直後に呼ぶこと。
        ///   グルーピング閉じる前に save すると、save 操作自体が Undo 履歴に
        ///   含まれてしまう可能性があるため。
        /// - エラー処理: save 失敗は UI からは復旧できないため、Analytics 送信のみ行う。
        ///   ユーザーには成功扱いで通知されるが、実際は次回起動時に取り込み内容が
        ///   消えている可能性がある。これは想定上きわめて稀（ディスク満杯 等）。
        ///
        /// - Parameter domain: Analytics ログのドメイン名
        ///   ("import_single_save" / "import_backup_save")
        private func persistAfterImport(domain: String) {
            // 変更が無ければ無駄な I/O を避ける
            guard modelContext.hasChanges else { return }
            do {
                try modelContext.save()
            } catch {
                // 保存失敗は Crashlytics/Analytics へ送り、傾向分析に使う
                logError(error, domain: domain, message: "インポート後の context.save 失敗")
            }
        }

        // MARK: - 共通ヘルパー

        /// ヘッダーの整合性チェック
        private func validateHeader(productName: String, copyright: String, version: String) throws {
            if productName != PACK_JSON_DTO_PRODUCT_NAME {
                throw ImportError.productNameMismatch
            }
            if copyright != PACK_JSON_DTO_COPYRIGHT {
                throw ImportError.copyrightMismatch
            }
            if version != PACK_JSON_DTO_VERSION {
                throw ImportError.versionMismatch
            }
        }

        /// IDまたは名前でパックを照合して上書き、なければ挿入位置に新規作成する
        @discardableResult
        private func upsertPack(dto: PackJsonDTO, existingPacks: inout [M1Pack]) -> (pack: M1Pack, wasOverwritten: Bool) {
            // IDが含まれている場合（バックアップ）はIDで照合する
            if let dtoId = dto.id,
               let existing = existingPacks.first(where: { $0.id == dtoId }) {
                return (PackImporter.overwrite(pack: existing, with: dto, in: modelContext), true)
            }
            // IDなし（単体パック共有）は名前で照合する
            if dto.id == nil,
               let existing = existingPacks.first(where: { $0.name == dto.name }) {
                return (PackImporter.overwrite(pack: existing, with: dto, in: modelContext), true)
            }
            // 存在しなければ挿入位置設定に従って新規作成
            let orderedPacks = existingPacks.sorted { $0.order < $1.order }
            let insertionIndex = (insertionPosition == .head) ? 0 : orderedPacks.count
            let newOrder = sparseOrderForInsertion(items: orderedPacks, index: insertionIndex) {
                normalizeSparseOrders(orderedPacks)
            }
            let newPack = PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
            existingPacks.append(newPack)
            return (newPack, false)
        }

        // MARK: - Alert / Error

        private enum ImportAlert: Identifiable {
            case success(packName: String, wasOverwritten: Bool)
            case successBatch(added: Int, overwritten: Int)
            case failure(message: String)

            var id: String {
                switch self {
                case .success(let packName, _): return "success-\(packName)"
                case .successBatch(let a, let o): return "batch-\(a)-\(o)"
                case .failure: return "failure"
                }
            }

            var title: String {
                switch self {
                case .success, .successBatch: return String(localized: "import.done")
                case .failure: return String(localized: "import.failed")
                }
            }

            var message: String {
                switch self {
                case .success(let packName, let wasOverwritten):
                    let format = wasOverwritten
                        ? String(localized: "value.overwritten")
                        : String(localized: "value.imported")
                    return String(format: format, packName)
                case .successBatch(let added, let overwritten):
                    var parts: [String] = []
                    if added > 0 {
                        parts.append(String(format: String(localized: "count.new"), added))
                    }
                    if overwritten > 0 {
                        parts.append(String(format: String(localized: "count.overwritten"), overwritten))
                    }
                    return parts.joined(separator: "・")
                case .failure(let message):
                    return message
                }
            }
        }

        private enum ImportError: LocalizedError {
            case productNameMismatch, copyrightMismatch, versionMismatch, invalidFormat

            var errorDescription: String? {
                switch self {
                case .productNameMismatch: return "Product name mismatch."
                case .copyrightMismatch:   return "Copyright mismatch."
                case .versionMismatch:     return "Version mismatch."
                case .invalidFormat:       return String(localized: "unsupported.file.format")
                }
            }
        }
    }
    
    /// カスタム設定
    struct CustomSetView: View {
        @Environment(\.modelContext) private var modelContext

        // 不揮発保存、初期値
        @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
        @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = DEF_showNeedWeight
        @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = DEF_weightDisplayInKg
        @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
        @AppStorage(AppStorageKey.linkCheckOffWithZero) private var linkCheckOffWithZero: Bool = DEF_linkCheckOffWithZero
        @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
        @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .default
        @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
        @AppStorage(AppStorageKey.rowTextLines) private var rowTextLines: RowTextLines = .default

        // GALoggerのため変更前の設定値を記録する
        @State var ona_insertionPosition: InsertionPosition?
        @State var ona_showNeedWeight: Bool?
        @State var ona_weightDisplayInKg: Bool?
        @State var ona_linkCheckWithStock: Bool?
        @State var ona_linkCheckOffWithZero: Bool?
        @State var ona_displayMode: DisplayMode?
        @State var ona_appearanceMode: AppearanceMode?
        @State var ona_fontScale: FontScale?
        @State var ona_rowTextLines: RowTextLines?

        var body: some View {

            VStack(alignment: .leading, spacing: 20) {
                // 表示モード（初心者／上級者）
                AdaptiveRadioRow(options: DisplayMode.allCases,
                                 selection: $displayMode,
                                 minOptionWidth: 88) {
                    Label {
                        Text("view.mode")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "lightbulb.2")
                            .symbolRenderingMode(.hierarchical)
                    }
                } label: { mode in
                    Text(mode.localizedKey)
                }

                // 外観モード（システム追従／ライト／ダーク）
                AdaptiveRadioRow(options: AppearanceMode.allCases,
                                 selection: $appearanceMode,
                                 minOptionWidth: 70) {
                    Label {
                        Text("appearance")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "circle.lefthalf.filled")
                            .symbolRenderingMode(.hierarchical)
                    }
                } label: { mode in
                    Text(mode.localizedKey)
                }

                // 文字サイズ（自動／標準／大／特大）
                AdaptiveRadioRow(options: FontScale.allCases,
                                 selection: $fontScale,
                                 minOptionWidth: 60) {
                    Label {
                        Text("font.size")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "textformat.size")
                            .symbolRenderingMode(.hierarchical)
                    }
                } label: { scale in
                    Text(scale.localizedKey)
                }

                // 行の表示行数を切り替える
                AdaptiveRadioRow(options: RowTextLines.allCases,
                                 selection: $rowTextLines,
                                 minOptionWidth: 56) {
                    Label {
                        Text("details")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "text.justify")
                            .symbolRenderingMode(.hierarchical)
                    }
                } label: { setting in
                    Text(setting.localizedKey)
                }

                // 新規追加の位置（アイコン選択）
                AdaptiveRadioRow(options: InsertionPosition.allCases,
                                 selection: $insertionPosition,
                                 minOptionWidth: 70) {
                    Label {
                        Text("add.position")
                            .font(.callout)
                            .foregroundStyle(COLOR_ADD_ACTION)
                    } icon: {
                        Image(systemName: "plus.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(COLOR_ADD_ACTION)
                    }
                } label: { position in
                    Image(systemName: position.iconSFname)
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                }
                // 必要重量を表示
                Toggle(isOn: $showNeedWeight) {
                    Label {
                        Text("show.needed.weight")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // 重量計1000gからkgで表示
                Toggle(isOn: $weightDisplayInKg) {
                    Label {
                        Text("scale.from.1000g.kg")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // チェックと在庫を連動
                Toggle(isOn: $linkCheckWithStock) {
                    Label {
                        Text("turn.check.fill.stock")
                            .font(.body)
                    } icon: {
                        ZStack{
                            Image(systemName: "checkmark.circle")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                // チェックOFF時の在庫リセット設定
                Toggle(isOn: $linkCheckOffWithZero) {
                    Label {
                        Text("turn.check.off.set.stock.0")
                            .font(.body)
                    } icon: {
                        Image(systemName: "circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .onAppear {
                // GALoggerのため変更前の設定値を記録する
                ona_insertionPosition  = insertionPosition
                ona_showNeedWeight     = showNeedWeight
                ona_weightDisplayInKg  = weightDisplayInKg
                ona_linkCheckWithStock = linkCheckWithStock
                ona_linkCheckOffWithZero = linkCheckOffWithZero
                ona_displayMode        = displayMode
                ona_appearanceMode     = appearanceMode
                ona_fontScale          = fontScale
                ona_rowTextLines       = rowTextLines
            }
            .onDisappear {
                // 変更あればGALogger送信する
                if let ona = ona_insertionPosition, ona != insertionPosition {
                    // 設定変更を匿名集計できる形で送信する
                    GALogger.log(.setting_changed(key: "insertion_position", value: insertionPosition.rawValue))
                }
                if let ona = ona_showNeedWeight, ona != showNeedWeight {
                    // 初心者向け重量表示の変更を集計する
                    GALogger.log(.setting_changed(key: "show_need_weight", value: showNeedWeight.description))
                }
                if let ona = ona_weightDisplayInKg, ona != weightDisplayInKg {
                    // 単位変更の傾向を集計する
                    GALogger.log(.setting_changed(key: "weight_display_in_kg", value: weightDisplayInKg.description))
                }
                if let ona = ona_linkCheckWithStock, ona != linkCheckWithStock {
                    // チェックON時の在庫連動設定を集計する
                    GALogger.log(.setting_changed(key: "link_check_with_stock", value: linkCheckWithStock.description))
                }
                if let ona = ona_linkCheckOffWithZero, ona != linkCheckOffWithZero {
                    // チェックOFF時の在庫クリア設定を集計する
                    GALogger.log(.setting_changed(key: "link_check_off_with_zero", value: linkCheckOffWithZero.description))
                }
                if let ona = ona_displayMode, ona != displayMode {
                    // 表示モード切り替えを集計する
                    GALogger.log(.setting_changed(key: "display_mode", value: displayMode.rawValue))
                }
                if let ona = ona_appearanceMode, ona != appearanceMode {
                    // 外観モード切り替えを集計する
                    GALogger.log(.setting_changed(key: "appearance_mode", value: appearanceMode.rawValue))
                }
                if let ona = ona_fontScale, ona != fontScale {
                    // 文字サイズ変更を集計する
                    GALogger.log(.setting_changed(key: "font_scale", value: fontScale.rawValue))
                }
                if let ona = ona_rowTextLines, ona != rowTextLines {
                    // 行数設定の変更を集計してUI調整の傾向を知る
                    GALogger.log(.setting_changed(key: "row_text_lines", value: rowTextLines.rawValue))
                }
            }
        }
    }
    /// 応援・寄付
    struct DonationView: View {
        @State private var showAd = false
        @State private var showAdMovie = false
        @State private var showDonate = false
        @State private var showRewardThankYou = false // 広告視聴後にお礼アラートを出すためのフラグ
        @State private var showTipSheet = false

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text("support.developer")
                        .font(.body.weight(.medium))
                } icon: {
                    Image(systemName: "heart.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 投げ銭で応援する（ボタン）
                    Button(action: {
                        showTipSheet = true
                    }) {
                        Label("tip.support", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .padding(.horizontal, 32)
                    .sheet(isPresented: $showTipSheet) {
                        TipSheetView()
                    }

                    // 広告を見て応援する（ボタン）
                    Button(action: {
                        showAd = true
                    }) {
                        Text("watch.ad.support")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brown)
                    .padding(.horizontal, 32)
                }
                .sheet(isPresented: $showAd) {
                    // バナーも動画もまとめて閲覧できる新しいシートを表示
                    AdMobAdSheetView(
                        onRewardEarned: {
                            // 広告の視聴完了を検知してお礼を伝える
                            showRewardThankYou = true
                        },
                        rewardTrialDescription: String(localized: "watch.end.support.dev.chip.only")
                    )
                }
                // 視聴完了後にささやかな感謝を伝える
                .alert(
                    String(localized: "thanks.watching"),
                    isPresented: $showRewardThankYou
                ) {
                    Button(String(localized: "OK")) {}
                } message: {
                    Text(String(localized: "thanks.support.ll.keep.improving.hope"))
                }
            }
        }
    }

    /// 投げ銭シート（モチメモ独自のコイントス＋カバンへ詰める演出）
    struct TipSheetView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var store = TipStore.shared
        @State private var showThankYou = false
        @State private var activeThrow: CoinThrow? = nil
        @State private var targetScale: CGFloat = 1.0
        @State private var lidLift: CGFloat = 0
        /// SF Symbol の bounce アニメをトリガーするためのカウンタ
        @State private var bagBounceTrigger: Int = 0

        /// 投げ銭ボタンが押された瞬間にコインの軌跡を表現するための情報
        private struct CoinThrow: Identifiable {
            let id = UUID()
            let buttonIndex: Int
            let color: Color
            let product: Product
        }

        var body: some View {
            NavigationStack {
                GeometryReader { geo in
                    ZStack {
                        sheetContent
                        if let toss = activeThrow {
                            // ボタン位置からカバンの口への始点・終点を算出して詰め込み軌道を描く
                            let startX = toss.buttonIndex == 0
                                ? geo.size.width * 0.33
                                : geo.size.width * 0.67
                            let bagMouthY: CGFloat = 92
                            TossedCoin(
                                key: toss.id,
                                start: CGPoint(x: startX, y: geo.size.height - 130),
                                end: CGPoint(x: geo.size.width * 0.5, y: bagMouthY),
                                color: toss.color
                            ) {
                                // カバンに「詰める」着弾演出：
                                //  1) カバンが「ぷくっ」と膨らむ（targetScale）
                                //  2) フタを少し持ち上げて、口から入った感じを出す
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) {
                                    targetScale = 1.22
                                    lidLift = -8
                                }
                                bagBounceTrigger += 1
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                                        targetScale = 1.0
                                        lidLift = 0
                                    }
                                }
                            } onCompleted: {
                                let product = toss.product
                                activeThrow = nil
                                Task {
                                    if await store.purchase(product) {
                                        showThankYou = true
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(Text("tip.support"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                .task { await store.loadProducts() }
                .alert(
                    String(localized: "thank"),
                    isPresented: $showThankYou
                ) {
                    Button(String(localized: "OK")) { dismiss() }
                } message: {
                    Text(String(localized: "thank.support.will.keep.improving.app"))
                }
            }
        }

        @ViewBuilder
        private var sheetContent: some View {
            VStack(spacing: 0) {
                bagTarget
                    .padding(.top, 32)

                TossArcHint()
                    .frame(height: 52)
                    .padding(.horizontal, 56)
                    .padding(.top, 6)

                Text("support.encourages.us.keep.developing.app")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                Spacer()
                coinSection
                    .padding(.bottom, 56)
            }
        }

        /// 投げ銭の着弾先ターゲット。旅行カバンの口にコインを吸い込ませる
        private var bagTarget: some View {
            ZStack {
                Circle()
                    .fill(.pink.opacity(0.10))
                    .frame(width: 108, height: 108)
                Circle()
                    .stroke(.pink.opacity(0.22), lineWidth: 1.5)
                    .frame(width: 108, height: 108)
                // モチメモのアプリアイコン同様の「case」シンボル。コイン着弾でバウンスする
                Image(systemName: "case")
                    .font(.system(size: 50))
                    .foregroundStyle(.pink)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce.up.byLayer,
                                  options: .speed(1.3),
                                  value: bagBounceTrigger)
                // コインの吸い込み口をカバン上部に見せる
                Capsule()
                    .fill(.pink.opacity(0.82))
                    .frame(width: 42, height: 4)
                    .offset(y: -7)
                // 着弾時だけフタが少し跳ねる
                Capsule()
                    .fill(.pink.opacity(0.34))
                    .frame(width: 38, height: 5)
                    .offset(y: -17 + lidLift)
                // 応援の気持ちを示す小さなハート
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.pink)
                    .offset(x: 24, y: -24)
            }
            .scaleEffect(targetScale)
        }

        @ViewBuilder
        private var coinSection: some View {
            if store.isLoadingProducts {
                ProgressView()
            } else if store.products.isEmpty {
                Text("not.available.time")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 40) {
                    ForEach(Array(store.products.enumerated()), id: \.element.id) { index, product in
                        // 最後の商品（金額が大きい想定）は金色、それ以外は銅色のコインで描画する
                        let isLarge = index == store.products.count - 1
                        let coinColor: Color = isLarge
                            ? Color(red: 0.90, green: 0.72, blue: 0.18)
                            : Color(red: 0.72, green: 0.45, blue: 0.20)
                        TipCoinButton(
                            price: product.displayPrice,
                            color: coinColor,
                            disabled: activeThrow != nil || store.isPurchasing
                        ) {
                            activeThrow = CoinThrow(
                                buttonIndex: index,
                                color: coinColor,
                                product: product
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - 投げ銭シート用：コインボタン

    /// 円形のコイン風投げ銭ボタン
    private struct TipCoinButton: View {
        let price: String
        let color: Color
        let disabled: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [color, color.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                    Circle()
                        .stroke(color.opacity(0.25), lineWidth: 1)
                        .padding(10)
                    Text(price)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(color)
                }
                .frame(width: 100, height: 100)
                .shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(TipCoinPressStyle())
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1.0)
        }
    }

    /// コインボタンを押下した時のスケール感を出すボタンスタイル
    private struct TipCoinPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
        }
    }

    // MARK: - 投げ銭シート用：放物線ヒント

    /// コインが飛ぶ軌道を破線アーチで案内する装飾ビュー
    private struct TossArcHint: View {
        var body: some View {
            Canvas { ctx, size in
                let width = size.width
                let height = size.height
                // 左ボタン→ターゲット、右ボタン→ターゲットの2本の弧を描く
                for (startRatio, controlRatio) in [(0.25, 0.82), (0.75, 0.18)] as [(Double, Double)] {
                    var path = Path()
                    path.move(to: CGPoint(x: width * startRatio, y: height))
                    path.addQuadCurve(
                        to: CGPoint(x: width * 0.5, y: 0),
                        control: CGPoint(x: width * controlRatio, y: height * 0.12)
                    )
                    ctx.stroke(
                        path,
                        with: .color(.secondary.opacity(0.28)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 5])
                    )
                }
            }
        }
    }

    // MARK: - 投げ銭シート用：飛ぶコイン

    /// ボタンからターゲットへ放物線を描いて飛ぶコイン本体
    private struct TossedCoin: View {
        let key: UUID
        let start: CGPoint
        let end: CGPoint
        let color: Color
        let onImpact: () -> Void
        let onCompleted: () -> Void

        private struct KeyframeValue {
            var offsetX: CGFloat = 0
            var offsetY: CGFloat = 0
            var rotation: Double = 0
            var scale: CGFloat = 1
            var opacity: Double = 1
        }

        @State private var fire = false
        /// 接近のみの所要時間。到達した瞬間に除去するため、シュリンク/フェード時間は含めない
        private let duration: Double = 1.0

        private var deltaX: CGFloat { end.x - start.x }
        private var deltaY: CGFloat { end.y - start.y }

        var body: some View {
            Circle()
                .fill(LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.70)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    ZStack {
                        Circle().stroke(.white.opacity(0.28), lineWidth: 1.5).padding(5)
                        Text(verbatim: "¥").font(.title3.bold()).foregroundStyle(.white)
                    }
                )
                .shadow(color: color.opacity(0.55), radius: 10, x: 0, y: 4)
                .frame(width: 50, height: 50)
                .keyframeAnimator(initialValue: KeyframeValue(), trigger: fire) { content, value in
                    content
                        .offset(x: value.offsetX, y: value.offsetY)
                        .rotationEffect(.degrees(value.rotation))
                        .scaleEffect(value.scale)
                        .opacity(value.opacity)
                } keyframes: { _ in
                    // 接近のみ（単調にカバン中心へ進む直線運動）：
                    //   - 後退するキーフレームを一切含めず、目的地で完全に止める
                    //   - 到達後はその場でフェードアウトして消える

                    // 横方向：単調に deltaX へ近づく（後退しない）
                    KeyframeTrack(\.offsetX) {
                        LinearKeyframe(0,             duration: 0.01)
                        LinearKeyframe(deltaX * 0.40, duration: duration * 0.30)
                        LinearKeyframe(deltaX * 0.75, duration: duration * 0.30)
                        LinearKeyframe(deltaX,        duration: duration * 0.20) // カバン中心へ到達
                        LinearKeyframe(deltaX,        duration: duration * 0.19) // 停止＋フェード中も固定
                    }

                    // 縦方向：単調に deltaY へ近づく（カバンより上にも下にも動かさない）
                    KeyframeTrack(\.offsetY) {
                        LinearKeyframe(0,             duration: 0.01)
                        LinearKeyframe(deltaY * 0.40, duration: duration * 0.30)
                        LinearKeyframe(deltaY * 0.75, duration: duration * 0.30)
                        LinearKeyframe(deltaY,        duration: duration * 0.20) // カバン中心へ到達
                        LinearKeyframe(deltaY,        duration: duration * 0.19) // 停止＋フェード中も固定
                    }

                    // 回転：カバンへ「詰める」動きに集中させるため回さない
                    KeyframeTrack(\.rotation) {
                        LinearKeyframe(0, duration: duration)
                    }

                    // 拡大率：到達まで等倍維持、フェード中も拡縮させない
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1.0, duration: duration)
                    }

                    // 不透明度：到達した直後（最後の 14%）でその場フェードアウト
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1.0, duration: duration * 0.86)
                        LinearKeyframe(0.0, duration: duration * 0.14)
                    }
                }
                .position(start)
                .allowsHitTesting(false)
                .onAppear {
                    fire = true
                    // コインが消え切ってからカバンを反応させ、跳ね返りに見せない
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.96) {
                        onImpact()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                        onCompleted()
                    }
                }
                .id(key)
        }
    }

}

#Preview {
    SettingView()
        .environmentObject(CreditStore())
}
