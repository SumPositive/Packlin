import SwiftUI
import SwiftData

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

    @State private var searchText: String = ""
    @State private var sort: SortOrder = .popular
    /// 自分の端末言語のみに絞り込むか
    @State private var localeFilterOn: Bool = true

    @State private var items: [PublicPackSummary] = []
    @State private var offset: Int = 0
    @State private var canLoadMore: Bool = false
    @State private var isLoading: Bool = false
    /// 一覧読み込み自体のエラー（画面上部に表示）
    @State private var errorMessage: String?
    /// 削除確認中の自分の公開パック
    @State private var pendingDeleteItem: PublicPackSummary?
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
                // フッターのバナー広告
                Divider()
                AdMobBannerView(
                    adUnitID: ADMOB_BANNER_UnitID,
                    size: CGSize(width: 320, height: 50)
                )
                .frame(height: 50)
                .padding(.vertical, 4)
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
        // 自分の公開パックの削除確認
        .alert("public.pack.delete.confirm",
               isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if $0 == false { pendingDeleteItem = nil } }
               ),
               presenting: pendingDeleteItem) { item in
            Button("delete", role: .destructive) {
                Task { await deletePack(item) }
            }
            Button("cancel", role: .cancel) { pendingDeleteItem = nil }
        } message: { item in
            Text(item.name.isEmpty ? String(localized: "no.name") : item.name)
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

                Toggle(isOn: $localeFilterOn) {
                    Text(localeFilterLabel)
                        .font(.caption)
                }
                .toggleStyle(.button)
                .onChange(of: localeFilterOn) { _, _ in Task { await reload() } }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name.isEmpty ? String(localized: "no.name") : item.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.memo.isEmpty == false {
                Text(item.memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // 左側に「件数行＋公開日行」の2行、右側のボタンはその2行に跨って上下中央
            HStack(alignment: .center, spacing: 8) {
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

                Spacer(minLength: 8)

                // 自分が公開したパックは削除ボタン、他人のパックは取り込みボタン
                if item.isMine {
                    deleteButton(item)
                } else {
                    importButton(item)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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

    private func importButton(_ item: PublicPackSummary) -> some View {
        Button {
            Task { await importPack(item) }
        } label: {
            Label {
                Text("public.pack.import")
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .disabled(rowStatus[item.id] != nil)
    }

    private func deleteButton(_ item: PublicPackSummary) -> some View {
        Button(role: .destructive) {
            // 確認アラートを出してから削除する
            pendingDeleteItem = item
        } label: {
            Label {
                Text("delete")
            } icon: {
                Image(systemName: "trash")
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(rowStatus[item.id] != nil)
    }

    // MARK: - データ取得

    /// 端末の言語コード（絞り込みの既定値）。アプリ対応言語(ja/en)でなくデバイス本来のロケール
    private func currentLocaleCode() -> String? {
        devicePreferredLanguageCode()
    }

    /// 絞り込みトグルのラベル「自言語(JA)のみ」（JA はデバイスロケール、無ければ従来表記）
    private var localeFilterLabel: String {
        let code = (currentLocaleCode() ?? "").uppercased()
        if code.isEmpty {
            return String(localized: "public.pack.locale.filter")
        }
        return String(format: String(localized: "public.pack.locale.filter.fmt"), code)
    }

    private func queryArg() -> String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localeArg() -> String? {
        localeFilterOn ? currentLocaleCode() : nil
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

    /// 公開パックを取り込む（新しいローカルIDが採番される）
    @MainActor
    private func importPack(_ item: PublicPackSummary) async {
        if rowStatus[item.id] != nil { return }
        rowStatus[item.id] = .loading
        do {
            let userId = creditStore.regenerateUserIdIfNeeded()
            let dto = try await AzukiApi.shared.importPublicPack(publishedId: item.id, userId: userId)
            insert(dto: dto)
            // 完了表示は少し見せてから自動で消し、再取り込みできる状態へ戻す
            setRowState(item.id, .done(String(localized: "public.pack.imported")), autoClearAfter: 1.8)
        } catch let apiError as AzukiAPIError {
            setRowState(item.id, .error(apiError.errorDescription ?? String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        } catch {
            setRowState(item.id, .error(String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        }
    }

    /// 自分が公開したパックを削除する
    @MainActor
    private func deletePack(_ item: PublicPackSummary) async {
        pendingDeleteItem = nil
        if rowStatus[item.id] != nil { return }
        rowStatus[item.id] = .loading
        do {
            // 認証必須エンドポイントのため、トークン未取得ならまず credit/check で発行する
            let userId = creditStore.regenerateUserIdIfNeeded()
            if AzukiApi.shared.hasValidAccessToken() == false {
                _ = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
            }
            try await AzukiApi.shared.unpublishPack(publishedId: item.id)
            // セルは消さず、カバー上に「削除しました」を表示したままにする
            rowStatus[item.id] = .done(String(localized: "public.pack.deleted"))
        } catch let apiError as AzukiAPIError {
            setRowState(item.id, .error(apiError.errorDescription ?? String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        } catch {
            setRowState(item.id, .error(String(localized: "network.seems.down.please.try.again")), autoClearAfter: 2.5)
        }
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
