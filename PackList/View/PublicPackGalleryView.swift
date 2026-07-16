import SwiftUI
import SwiftData
import UIKit

/// 公開パックから取得する画面
/// 一覧／検索（上位20件ずつ）から選び、自分のパックとして取り込む
struct PublicPackGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var creditStore: CreditStore
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default

    /// 並び順
    private enum SortOrder: String, CaseIterable, Identifiable {
        case popular // 取得数の多い順
        case recent  // 新着順

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .popular: return "public.pack.sort.popular"
            case .recent:  return "public.pack.sort.recent"
            }
        }
    }

    /// 言語の絞り込み。多言語化に備えて言語をここに追加していく。
    /// `all` は全言語、それ以外は locale コード（サーバの locale 列と一致させる）で1言語に絞る。
    private enum LocaleFilter: Hashable, Identifiable {
        case all
        case language(String) // "ja", "en" など

        var id: String {
            switch self {
            case .all: return "all"
            case .language(let code): return code
            }
        }

        /// サーバへ渡す locale 引数（all は nil＝全言語）
        var localeArg: String? {
            switch self {
            case .all: return nil
            case .language(let code): return code
            }
        }

        /// アプリが標準で用意する言語選択肢（全言語＋対応言語）
        private static let baseCases: [LocaleFilter] = [
            .all,
            .language("ja"),
            .language("en"),
            .language("de"),
            .language("es"),
            .language("fr"),
            .language("it"),
            .language("ko"),
            .language("zh-Hant"),
        ]

        // 対応言語は母語名を固定し、zh-Hant の表示ゆれを避ける
        private static let nativeLanguageNames: [String: String] = [
            "ja": "日本語",
            "en": "English",
            "de": "Deutsch",
            "es": "Español",
            "fr": "Français",
            "it": "Italiano",
            "ko": "한국어",
            "zh-Hant": "繁體中文",
        ]

        /// プルダウンに出す全選択肢。標準の選択肢に加え、
        /// デバイス言語が標準に無ければ末尾に追加する
        /// （例: ko 端末なら「한국어」を出して、その言語のパックを絞り込めるようにする）。
        static var allCases: [LocaleFilter] {
            var cases = baseCases
            if let code = devicePreferredLanguageCode(),
               cases.contains(where: { $0.id == code }) == false {
                cases.append(.language(code))
            }
            return cases
        }

        /// 表示名。言語はネイティブ表記を優先し、無ければコード。
        var title: String {
            switch self {
            case .all:
                return String(localized: "public.pack.locale.all")
            case .language(let code):
                if let native = Self.nativeLanguageNames[code] {
                    return native
                }
                let native = Locale(identifier: code).localizedString(forLanguageCode: code)
                return native?.capitalized ?? code.uppercased()
            }
        }

        /// 起動時の既定。デバイス言語を初期選択にする（allCases に必ず含まれる）。
        /// デバイス言語が取得できないときだけ全言語にフォールバックする。
        static func defaultForDevice() -> LocaleFilter {
            guard let code = devicePreferredLanguageCode() else { return .all }
            return allCases.first { $0.id == code } ?? .all
        }
    }

    @State private var searchText: String = ""
    @State private var sort: SortOrder = .popular
    /// 言語の絞り込み。既定はデバイス言語（対応言語に無ければ全言語）。
    @State private var localeFilter: LocaleFilter = LocaleFilter.defaultForDevice()

    /// 公開パックの取込回数（累計）。一定回数ごとにリワード広告を挟むために使う
    @AppStorage(AppStorageKey.publicPackImportCount) private var importCount: Int = 0
    /// 広告ゲート表示中に取込予定のパック（視聴完了後にこれを取り込む）
    @State private var pendingImportItem: PublicPackSummary?

    @State private var items: [PublicPackSummary] = []
    @State private var offset: Int = 0
    @State private var canLoadMore: Bool = false
    @State private var isLoading: Bool = false
    /// 一覧読み込み自体のエラー（画面上部に表示）
    @State private var errorMessage: String?
    /// 詳細シートへ表示する公開パック
    @State private var sharingItem: PublicPackSummary?
    /// セルごとの処理状態（取り込み・削除のカバー表示用）
    @State private var rowStatus: [String: RowState] = [:]

    /// セルに被せるカバーの状態
    private enum RowState: Equatable {
        case loading            // 処理中（プログレス）
        case done(String)       // 完了メッセージ
        case error(String)      // エラーメッセージ
    }

    /// 公開日時の表示用フォーマッタ（ローカル時刻・分まで）
    private static let publishedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                Divider()
                listContent
                // フッターのバナー広告（スクショ撮影時は審査用スクショに広告を写さないため非表示）
                if SnapshotSupport.isRunningSnapshot == false && sharingItem == nil {
                    Divider()
                    AdMobBannerView(
                        adUnitID: ADMOB_BANNER_UnitID,
                        size: CGSize(width: 320, height: 50)
                    )
                    .frame(height: 50)
                    .padding(.vertical, 4)
                }
                // ※ 一覧の中身はスクショ時も実サーバから取得する（管理者が公開したサンプルを表示）
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("public.pack.gallery.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .appFontScale(fontScale)
        // 詳細、取込、共有、作者用削除を1つのシートへまとめる
        .sheet(item: $sharingItem) { item in
            PublicPackDetailSheet(
                item: item,
                onImport: {
                    // 詳細シートを閉じてから広告ゲートまたは取込処理を開始する
                    sharingItem = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        handleImportTapped(item)
                    }
                },
                onDelete: {
                    // 削除確認は詳細シート内で完了済み
                    sharingItem = nil
                    Task { await deletePack(item) }
                }
            )
                .appFontScale(fontScale)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 3回ごとの取込で表示するリワード広告ゲート。
        // 視聴完了なら取込＋回数を進める。広告が見られないときは取込のみ（回数は進めず次回再挑戦）。
        .sheet(item: $pendingImportItem) { item in
            ImportAdGateSheet(
                onRewarded: {
                    Task { await importPack(item, countsTowardAdGate: true) }
                },
                onSkippedNoAd: {
                    Task { await importPack(item, countsTowardAdGate: false) }
                }
            )
            .appFontScale(fontScale)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            // 初回表示で先頭ページを読み込む
            if items.isEmpty {
                await reload()
            }
        }
    }

    // MARK: - 操作バー（検索・並び・言語絞り込み）

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(text: $searchText) {
                    Text("public.pack.search.placeholder")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { Task { await reload() } }
                if searchText.isEmpty == false {
                    Button {
                        searchText = ""
                        Task { await reload() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            HStack(spacing: 12) {
                // 文字サイズ対応のラジオボタン（設定画面と同じ SettingRadioGroup を再利用）
                SettingRadioGroup(options: SortOrder.allCases,
                                  selection: $sort,
                                  minOptionWidth: 64,
                                  maxOptionWidth: 140,
                                  wrapsOptions: false) { option in
                    Text(option.titleKey)
                }
                .onChange(of: sort) { _, _ in Task { await reload() } }

                Spacer(minLength: 8)

                // 言語の絞り込み（多言語対応のためトグルからプルダウンへ）
                Menu {
                    Picker("public.pack.locale.picker", selection: $localeFilter) {
                        ForEach(LocaleFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(localeFilter.title)
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .onChange(of: localeFilter) { _, _ in Task { await reload() } }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 一覧

    @ViewBuilder
    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                ForEach(items) { item in
                    row(item)
                }

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 12)
                } else if items.isEmpty {
                    Text("public.pack.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else if canLoadMore {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Text("public.pack.load.more")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func row(_ item: PublicPackSummary) -> some View {
        Button {
            // セル全体のタップで詳細シートを開く
            sharingItem = item
            GALogger.log(.feature_use(name: "public_pack_detail", source: "public_pack_gallery", detail: "open"))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // 名前行の末尾に詳細表示を示す矢印だけを置く
                HStack(alignment: .top, spacing: 8) {
                    Text(item.name.isEmpty ? String(localized: "no.name") : item.name)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                if item.memo.isEmpty == false {
                    Text(item.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Label("\(item.itemCount)", systemImage: "checklist")
                        Label(weightText(item.totalWeight), systemImage: "scalemass")
                        Label("\(item.downloadCount)", systemImage: "arrow.down.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // 公開日時（分まで）と、その右に「言語 作者」（例: JA sumpo）
                    HStack(spacing: 8) {
                        if let publishedAt = item.publishedAt {
                            Text(Self.publishedAtFormatter.string(from: publishedAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(publisherText(item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(rowStatus[item.id] != nil)
        .accessibilityLabel(Text(item.name.isEmpty ? String(localized: "no.name") : item.name))
        .accessibilityHint(Text("public.pack.share.accessibility.hint"))
        // 処理中・結果表示の半透明カバー
        .overlay {
            if let state = rowStatus[item.id] {
                coverView(state)
            }
        }
        .padding(.horizontal, 16)
    }

    /// セルに被せる半透明カバー（プログレス／完了／エラー）
    @ViewBuilder
    private func coverView(_ state: RowState) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.systemBackground).opacity(0.8))
            .overlay {
                switch state {
                case .loading:
                    ProgressView()
                case .done(let message):
                    Label {
                        Text(message)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .multilineTextAlignment(.center)
                case .error(let message):
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                }
            }
    }

    // MARK: - データ取得

    private func queryArg() -> String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localeArg() -> String? {
        localeFilter.localeArg
    }

    /// 条件を変えて先頭から読み直す
    @MainActor
    private func reload() async {
        offset = 0
        items = []
        canLoadMore = false
        errorMessage = nil
        await fetchPage(reset: true)
    }

    /// 続きを読み込む
    @MainActor
    private func loadMore() async {
        await fetchPage(reset: false)
    }

    @MainActor
    private func fetchPage(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await AzukiApi.shared.searchPublicPacks(
                query: queryArg(),
                locale: localeArg(),
                sort: sort.rawValue,
                offset: offset,
                userId: creditStore.userId
            )
            if reset {
                items = page
            } else {
                items.append(contentsOf: page)
            }
            offset += page.count
            // 取得件数がページサイズと同数なら、まだ続きがある可能性が高い
            canLoadMore = page.count == PUBLIC_PACK_PAGE_SIZE
        } catch let apiError as AzukiAPIError {
            errorMessage = apiError.errorDescription
        } catch {
            errorMessage = String(localized: "network.seems.down.please.try.again")
        }
    }

    /// 取込ボタンが押されたときの入口。
    /// この取込が PUBLIC_PACK_IMPORT_AD_INTERVAL の倍数番目（3・6・9…回目）なら
    /// リワード広告ゲートを挟み、視聴完了後に取込する。それ以外はそのまま取込む。
    private func handleImportTapped(_ item: PublicPackSummary) {
        if rowStatus[item.id] != nil { return }
        let nextCount = importCount + 1
        if nextCount % PUBLIC_PACK_IMPORT_AD_INTERVAL == 0 {
            // 3回ごと：広告ゲートを表示。視聴完了で pendingImportItem を取り込む
            pendingImportItem = item
        } else {
            Task { await importPack(item, countsTowardAdGate: true) }
        }
    }

    /// 公開パックを取り込む（新しいローカルIDが採番される）
    /// - Parameter countsTowardAdGate: 取込成功時に取込回数を進めるか。
    ///   通常取込・広告視聴完了は true。広告在庫が無く広告なしで取り込む場合は false にして
    ///   回数を進めず、次回の取込でまた広告視聴に挑戦させる。
    @MainActor
    private func importPack(_ item: PublicPackSummary, countsTowardAdGate: Bool) async {
        if rowStatus[item.id] != nil { return }
        rowStatus[item.id] = .loading
        do {
            let userId = creditStore.regenerateUserIdIfNeeded()
            let dto = try await AzukiApi.shared.importPublicPack(publishedId: item.id, userId: userId)
            insert(dto: dto)
            // 取込成功をカウント（次回の広告ゲート判定に使う）。広告なしスキップ時は進めない。
            if countsTowardAdGate {
                importCount += 1
            }
            GALogger.log(.public_pack_result(action: "import", isSuccess: true, itemCount: item.itemCount,
                                             errorDomain: nil, errorCode: nil, message: nil))
            // 完了表示は少し見せてから自動で消し、再取り込みできる状態へ戻す
            setRowState(item.id, .done(String(localized: "public.pack.imported")), autoClearAfter: 1.8)
        } catch let apiError as AzukiAPIError {
            logPublicPackError(action: "import", apiError)
            setRowState(item.id, .error(apiError.errorDescription ?? String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        } catch {
            logPublicPackError(action: "import", error)
            setRowState(item.id, .error(String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        }
    }

    /// 自分が公開したパックを削除する
    @MainActor
    private func deletePack(_ item: PublicPackSummary) async {
        if rowStatus[item.id] != nil { return }
        rowStatus[item.id] = .loading
        do {
            // 認証必須エンドポイントのため、トークン未取得ならまず credit/check で発行する
            let userId = creditStore.regenerateUserIdIfNeeded()
            if AzukiApi.shared.hasValidAccessToken() == false {
                _ = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
            }
            try await AzukiApi.shared.unpublishPack(publishedId: item.id)
            GALogger.log(.public_pack_result(action: "delete", isSuccess: true, itemCount: item.itemCount,
                                             errorDomain: nil, errorCode: nil, message: nil))
            // 公開取消をローカルにも反映し、「公開中」バッジを消す。
            // publishedId が一致するローカルパックのフラグをクリアする。
            clearPublishedFlag(forPublishedId: item.id)
            // セルは消さず、カバー上に「削除しました」を表示したままにする
            rowStatus[item.id] = .done(String(localized: "public.pack.deleted"))
        } catch let apiError as AzukiAPIError {
            logPublicPackError(action: "delete", apiError)
            setRowState(item.id, .error(apiError.errorDescription ?? String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        } catch {
            logPublicPackError(action: "delete", error)
            setRowState(item.id, .error(String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        }
    }

    /// 指定した publishedId を持つローカルパックの「公開中」フラグをクリアする。
    /// 公開取消（unpublish）成功後に呼び、パックセルの「公開中」バッジを消す。
    @MainActor
    private func clearPublishedFlag(forPublishedId publishedId: String) {
        let descriptor = FetchDescriptor<M1Pack>(
            predicate: #Predicate { $0.publishedId == publishedId }
        )
        guard let packs = try? modelContext.fetch(descriptor) else { return }
        for pack in packs {
            pack.publishedId = nil
        }
    }

    /// 公開パック操作のエラーを Analytics へ記録する
    private func logPublicPackError(action: String, _ error: Error) {
        let info = publicPackErrorInfo(error)
        GALogger.log(.public_pack_result(action: action, isSuccess: false, itemCount: nil,
                                         errorDomain: info.domain, errorCode: info.code, message: info.message))
    }

    /// セルの状態を設定し、指定秒後に（同じ状態のままなら）自動で解除する
    @MainActor
    private func setRowState(_ id: String, _ state: RowState, autoClearAfter seconds: Double) {
        rowStatus[id] = state
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if rowStatus[id] == state {
                rowStatus[id] = nil
            }
        }
    }

    /// 取り込んだ DTO を設定の挿入位置に従って SwiftData へ保存する
    private func insert(dto: PackJsonDTO) {
        modelContext.undoManager?.groupingBegin()
        defer { modelContext.undoManager?.groupingEnd() }

        let descriptor = FetchDescriptor<M1Pack>()
        let packs = (try? modelContext.fetch(descriptor)) ?? []
        let orderedPacks = packs.sorted { $0.order < $1.order }
        let insertionIndex: Int = {
            switch insertionPosition {
            case .head:
                return 0
            case .tail:
                return orderedPacks.count
            }
        }()
        let newOrder = sparseOrderForInsertion(items: orderedPacks, index: insertionIndex) {
            normalizeSparseOrders(orderedPacks)
        }
        PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
    }

    /// 公開者表示「言語 作者」（例: JA sumpo）。言語が無ければ作者のみ
    private func publisherText(_ item: PublicPackSummary) -> String {
        if let locale = item.locale, locale.isEmpty == false {
            return "\(locale.uppercased()) \(item.author)"
        }
        return item.author
    }

    /// 総重量の表示用テキスト（1000g以上はkg表記）
    private func weightText(_ grams: Int) -> String {
        if 1000 <= grams {
            let kg = Double(grams) / 1000.0
            return String(format: "%.1fkg", kg)
        }
        return "\(grams)g"
    }

}

/// 公開パックの概要、取込、共有、作者用削除をまとめるシート
private struct PublicPackDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: PublicPackSummary
    let onImport: () -> Void
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var showShareHelp = false
    @State private var showDeleteConfirm = false

    /// 公開日時の表示用フォーマッタ
    private static let publishedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    /// 対応言語をコードではなく母語名で表示する
    private static let nativeLanguageNames: [String: String] = [
        "ja": "日本語",
        "en": "English",
        "de": "Deutsch",
        "es": "Español",
        "fr": "Français",
        "it": "Italiano",
        "ko": "한국어",
        "zh-Hant": "繁體中文",
    ]

    private var shareURL: URL {
        AzukiApi.shared.publicPackShareURL(publishedId: item.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    summarySection
                    importButton
                    Divider()
                    shareSection

                    if item.isMine {
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("delete", systemImage: "trash")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("public.pack.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if SnapshotSupport.isRunningSnapshot == false {
                    VStack(spacing: 0) {
                        Divider()
                        AdMobBannerView(
                            adUnitID: ADMOB_BANNER_UnitID,
                            size: CGSize(width: 320, height: 50)
                        )
                        .frame(height: 50)
                        .padding(.vertical, 4)
                    }
                    .background(.bar, ignoresSafeAreaEdges: .bottom)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .overlay {
            if showShareHelp {
                shareHelpDialog
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .alert("public.pack.delete.confirm", isPresented: $showDeleteConfirm) {
            Button("delete", role: .destructive) {
                // 作者確認済みの削除だけを親画面へ渡す
                dismiss()
                onDelete()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text(item.name.isEmpty ? String(localized: "no.name") : item.name)
        }
    }

    /// 共有リンクの説明を不透過背景で表示する
    private var shareHelpDialog: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("public.pack.share.title")
                    .font(.title3.weight(.bold))

                Text("public.pack.share.description")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showShareHelp = false
                    }
                } label: {
                    Text("OK")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(.separator), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .contain)
    }

    /// パック概要を省略せず表示する
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name.isEmpty ? String(localized: "no.name") : item.name)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.memo.isEmpty == false {
                Text(item.memo)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                detailRow("public.pack.field.group.count", systemImage: "square.stack.3d.up", value: String(item.groupCount))
                detailRow("public.pack.field.item.count", systemImage: "checklist", value: String(item.itemCount))
                detailRow("public.pack.field.weight", systemImage: "scalemass", value: weightText(item.totalWeight))
                detailRow("public.pack.field.download.count", systemImage: "arrow.down.circle", value: String(item.downloadCount))
                detailRow("public.pack.field.author", systemImage: "person", value: item.author)
                detailRow("public.pack.field.language", systemImage: "globe", value: languageName(item.locale))
                detailRow(
                    "public.pack.field.published.at",
                    systemImage: "calendar",
                    value: item.publishedAt.map { Self.publishedAtFormatter.string(from: $0) } ?? "-"
                )
            }
        }
    }

    /// 項目名と値をアイコン付きの1行で表示する
    private func detailRow(_ title: LocalizedStringKey, systemImage: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(verbatim: ":")
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    /// 共有リンクの直前に取込操作を配置する
    private var importButton: some View {
        Button {
            // シートを閉じてから親画面の取込フローへ渡す
            dismiss()
            onImport()
        } label: {
            Label("public.pack.import", systemImage: "square.and.arrow.down")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }

    /// localeコードを母語名へ変換する
    private func languageName(_ locale: String?) -> String {
        guard let locale, locale.isEmpty == false else { return "-" }
        return Self.nativeLanguageNames[locale] ?? locale.uppercased()
    }

    /// 共有URLとヘルプ、コピー操作をまとめる
    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("public.pack.share.title", systemImage: "link")
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showShareHelp = true
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .imageScale(.large)
                }
                .accessibilityLabel(Text("public.pack.share.help.button"))
            }

            // URL自体をタップした場合も同じコピー操作にする
            Button(action: copyLink) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(shareURL.absoluteString)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            Button(action: copyLink) {
                Label("public.pack.share.copy", systemImage: "doc.on.doc")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            if didCopy {
                Label("public.pack.share.copied", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }
        }
    }

    /// 公開パックURLをコピーし、短時間だけ完了表示を出す
    private func copyLink() {
        UIPasteboard.general.string = shareURL.absoluteString
        GALogger.log(.feature_use(name: "public_pack_share", source: "public_pack_gallery", detail: "copy"))
        withAnimation(.easeInOut(duration: 0.2)) {
            didCopy = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                didCopy = false
            }
        }
    }

    /// 総重量の表示用テキスト
    private func weightText(_ grams: Int) -> String {
        if 1000 <= grams {
            return String(format: "%.1fkg", Double(grams) / 1000.0)
        }
        return "\(grams)g"
    }
}
