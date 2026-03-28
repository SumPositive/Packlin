//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices
import SwiftData
import UniformTypeIdentifiers
import Foundation


let SettingView_HEIGHT: CGFloat = 670.0 // シート表示時の高さ指定

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
                return "先頭"
            case .tail:
                return "末尾"
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
    @Environment(\.colorScheme) private var colorScheme
    #if DEBUG
    @State private var showDebugUserIdAlert = false
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
                                        Text(String(localized: "UserIDとAI利用券を削除する"))
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red.opacity(0.7))
                                .controlSize(.small)
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
                .scrollIndicators(.never)
                // シートでは端末サイズに追従させるため、幅と高さの固定は行わない
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, -20)
            }
            .navigationTitle(Text("設定"))
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
            .alert(String(localized: "UserIDとAI利用券を削除しました"), isPresented: $showDebugUserIdAlert) {
                Button(role: .cancel) {
                    // 閉じるだけで処理は完了。画面はPublished経由で更新される
                } label: {
                    Text("OK")
                }
            } message: {
                // 次回利用時に自動で再発行されることを知らせつつ、クレジット初期化も明示する
                Text(String(localized: "UserIDは必要に応じて再発行されます"))
            }
            #endif
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

    /// アプリの紹介・取扱説明
    struct InformationView: View {
        @State private var showSafari = false
        
        var body: some View {
            Button(action: {
                // SafariでURLを表示する
                showSafari = true
                GALogger.log(.function(name: "settings", option: "tap_info"))
            }) {
                Label {
                    Text("アプリの紹介・取扱説明")
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
                let urlString = String(localized: "info.url")
                if let url = URL(string: urlString) {
                    SafariView(url: url)
                } else {
                    Text("情報を表示できません")
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
                        Text(isExporting ? "書き出し中..." : "全パックを書き出す（バックアップ）")
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
            .alert(String(localized: "書き出しに失敗しました"), isPresented: Binding(
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
                    log(.error, "バックアップ書き出し失敗: \(error)")
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
                GALogger.log(.function(name: "settings", option: "tap_import"))
            }) {
                Label {
                    Text("パックを読み込む（同パックは上書き）")
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
                        log(.error, "取り込み失敗: \(error)")
                        importAlert = .failure(message: error.localizedDescription)
                    }
                case .failure(let error):
                    log(.error, "ファイル選択失敗: \(error)")
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

        private func importSinglePack(data: Data) throws -> ImportAlert {
            let dto = try JSONDecoder().decode(PackJsonDTO.self, from: data)
            try validateHeader(productName: dto.productName, copyright: dto.copyright, version: dto.version)

            var existingPacks = (try? modelContext.fetch(FetchDescriptor<M1Pack>())) ?? []
            modelContext.undoManager?.groupingBegin()
            defer { modelContext.undoManager?.groupingEnd() }

            let (pack, wasOverwritten) = upsertPack(dto: dto, existingPacks: &existingPacks)
            return .success(packName: pack.name, wasOverwritten: wasOverwritten)
        }

        // MARK: - 全パックバックアップ (.packlinbackup)

        private func importBackup(data: Data) throws -> ImportAlert {
            let backup = try JSONDecoder().decode(BackupJsonDTO.self, from: data)
            try validateHeader(productName: backup.productName, copyright: backup.copyright, version: backup.version)

            var existingPacks = (try? modelContext.fetch(FetchDescriptor<M1Pack>())) ?? []
            modelContext.undoManager?.groupingBegin()
            defer { modelContext.undoManager?.groupingEnd() }

            var added = 0, overwritten = 0
            for dto in backup.packs {
                let (_, wasOverwritten) = upsertPack(dto: dto, existingPacks: &existingPacks)
                if wasOverwritten { overwritten += 1 } else { added += 1 }
            }
            return .successBatch(added: added, overwritten: overwritten)
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
                case .success, .successBatch: return String(localized: "取り込み完了")
                case .failure: return String(localized: "取り込みに失敗しました")
                }
            }

            var message: String {
                switch self {
                case .success(let packName, let wasOverwritten):
                    let format = wasOverwritten
                        ? String(localized: "%@ を上書きしました")
                        : String(localized: "%@ を取り込みました")
                    return String(format: format, packName)
                case .successBatch(let added, let overwritten):
                    var parts: [String] = []
                    if added > 0 {
                        parts.append(String(format: String(localized: "新規 %d 件"), added))
                    }
                    if overwritten > 0 {
                        parts.append(String(format: String(localized: "上書き %d 件"), overwritten))
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
                case .invalidFormat:       return String(localized: "対応していないファイル形式です。")
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
        @AppStorage(AppStorageKey.rowTextLines) private var rowTextLines: RowTextLines = .default

        // GALoggerのため変更前の設定値を記録する
        @State var ona_insertionPosition: InsertionPosition?
        @State var ona_showNeedWeight: Bool?
        @State var ona_weightDisplayInKg: Bool?
        @State var ona_linkCheckWithStock: Bool?
        @State var ona_linkCheckOffWithZero: Bool?
        @State var ona_displayMode: DisplayMode?
        @State var ona_rowTextLines: RowTextLines?

        var body: some View {

            VStack(alignment: .leading, spacing: 20) {
                // 表示モード（初心者／上級者）
                HStack(spacing: 8) {
                    Label {
                        Text("表示モード")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "lightbulb.2")
                            .symbolRenderingMode(.hierarchical)
                    }

                    Picker("表示モード", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.localizedKey)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 行の表示行数を切り替える
                HStack(spacing: 8) {
                    Label {
                        Text("明細表示")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "text.justify")
                            .symbolRenderingMode(.hierarchical)
                    }

                    Picker("明細表示", selection: $rowTextLines) {
                        ForEach(RowTextLines.allCases) { setting in
                            Text(setting.localizedKey)
                                .tag(setting)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 新規追加の位置
                HStack(spacing: 8) {
                    Label {
                        Text("新規追加位置")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "plus.circle")
                            .symbolRenderingMode(.hierarchical)
                    }

                    Picker("新規追加位置", selection: $insertionPosition) {
                        ForEach(InsertionPosition.allCases) { position in
                            Image(systemName: position.iconSFname)
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                // 必要重量を表示
                Toggle(isOn: $showNeedWeight) {
                    Label {
                        Text("必要重量を表示")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // 重量計1000gからkgで表示
                Toggle(isOn: $weightDisplayInKg) {
                    Label {
                        Text("重量計1000gからkg表示")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // チェックと在庫を連動
                Toggle(isOn: $linkCheckWithStock) {
                    Label {
                        Text("チェックONで在庫を満たす")
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
                        Text("チェックOFFで在庫を0にする")
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
                ona_rowTextLines       = rowTextLines
            }
            .onDisappear {
                // 変更あればGALogger送信する
                if let ona = ona_insertionPosition, ona != insertionPosition {
                    // 変更内容を文字列として連結し、ログに送信する
                    GALogger.log(.function(name: "setting",
                                           option: "insertionPosition:" + insertionPosition.rawValue))
                }
                if let ona = ona_showNeedWeight, ona != showNeedWeight {
                    // 初心者向け重量表示の変更を検知して記録する
                    GALogger.log(.function(name: "setting",
                                           option: "showNeedWeight:" + showNeedWeight.description))
                }
                if let ona = ona_weightDisplayInKg, ona != weightDisplayInKg {
                    // 単位変更のトグル操作をそのまま文字列化して送信
                    GALogger.log(.function(name: "setting",
                                           option: "weightDisplayInKg:" + weightDisplayInKg.description))
                }
                if let ona = ona_linkCheckWithStock, ona != linkCheckWithStock {
                    // チェックと在庫連動の状態変化をログする
                    GALogger.log(.function(name: "setting",
                                           option: "linkCheckWithStock:" + linkCheckWithStock.description))
                }
                if let ona = ona_linkCheckOffWithZero, ona != linkCheckOffWithZero {
                    // チェックOFF時の在庫クリア可否も計測しておく
                    GALogger.log(.function(name: "setting",
                                           option: "linkCheckOffWithZero:" + linkCheckOffWithZero.description))
                }
                if let ona = ona_displayMode, ona != displayMode {
                    // 表示モード切り替えを初心者・達人それぞれで判定して送信
                    GALogger.log(.function(name: "setting",
                                           option: "displayMode:" + displayMode.rawValue))
                }
                if let ona = ona_rowTextLines, ona != rowTextLines {
                    // 行数設定の変更を計測してUI調整の傾向を知る
                    GALogger.log(.function(name: "setting",
                                           option: "rowTextLines:" + rowTextLines.rawValue))
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

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text("開発者を応援する")
                        .font(.body.weight(.medium))
                } icon: {
                    Image(systemName: "heart.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 広告を見て寄付する（ボタン）
                    Button(action: {
                        withAnimation {
                            // SafariでURLを表示する
                            showAd = true
                        }
                    }) {
                        Text("広告を見て寄付")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brown)
                    .padding(.horizontal, 32)
                    .sheet(isPresented: $showAd) {
                        // バナーも動画もまとめて閲覧できる新しいシートを表示
                        AdMobAdSheetView(
                            onRewardEarned: {
                                // 広告の視聴完了を検知してお礼を伝える
                                showRewardThankYou = true
                            },
                            rewardTrialDescription: String(localized: "広告を最後まで見れば、開発者を直接応援できます！無理のない範囲でご協力いただけると嬉しいです")
                        )
                    }
                }
                // 視聴完了後にささやかな感謝を伝える
                .alert(
                    String(localized: "広告視聴ありがとう！"),
                    isPresented: $showRewardThankYou
                ) {
                    Button(String(localized: "OK")) {}
                } message: {
                    Text(String(localized: "応援いただき感謝しています。これからも改善を続けますので、よければまたのぞいてみてください！"))
                }
            }
        }
    }

}

#Preview {
    SettingView()
        .environmentObject(CreditStore())
}
