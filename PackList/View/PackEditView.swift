//  パック編集シート
//  名称、メモ、共有書き出し、複製、削除をまとめる
//

import SwiftUI
import SwiftData
import UIKit


struct PackEditView: View {
    @Bindable var pack: M1Pack

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var creditStore: CreditStore
    // 不揮発保存：チェックと在庫数を連動させる
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
    @AppStorage(AppStorageKey.linkCheckOffWithZero) private var linkCheckOffWithZero: Bool = DEF_linkCheckOffWithZero
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    // 作者ニックネーム（公開されます）。空文字は「匿名」
    @AppStorage(AppStorageKey.authorNickname) private var authorNickname: String = ""
    // ニックネームを一度でも明示確定したか（匿名のまま公開を選んだ場合も true）
    @AppStorage(AppStorageKey.authorNicknameConfigured) private var authorNicknameConfigured: Bool = false

    @State private var nameIsFocused: Bool = false
    @State private var memoIsFocused: Bool = false

    @State private var shareURL: URL?
    @State private var isPresentingShare = false
    @State private var isTogglingCheck = false

    // 公開保存まわり
    @State private var showNicknamePrompt = false
    @State private var showPublishConfirm = false
    @State private var nicknameDraft = ""
    @State private var isPublishing = false
    @State private var showPublishResult = false
    @State private var publishResultMessage = ""
    @State private var showPublishHelp = false

    /// === Fix 7: Undo グループ開閉のバランス保証フラグ ===
    /// onAppear / onDisappear は iOS のシート遷移や NavigationStack の
    /// プッシュ/ポップで必ずしも 1:1 に呼ばれないため、グルーピングの begin/end が
    /// アンバランスになり UndoStackService.transactionDepth が破綻するリスクがある。
    /// このフラグで「begin したかどうか」を覚えておき、end は対応する begin が
    /// あった場合のみ呼ぶ（再入時の二重 begin / 不対応 end を防止）。
    @State private var isUndoGroupingActive: Bool = false
    
    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    actionBar

                    editCard(title: "pack.name", minHeight: 74) {
                        PacklinMemoEditor(
                            placeholder: "enter.name.new.pack",
                            text: $pack.name,
                            isFocused: nameFocusBinding,
                            minHeight: 58,
                            maxLength: APP_MAX_NAME_LEN
                        )
                    }

                    editCard(title: "memo", minHeight: 112) {
                        PacklinMemoEditor(
                            placeholder: nil,
                            text: $pack.memo,
                            isFocused: memoFocusBinding,
                            minHeight: 96,
                            maxLength: APP_MAX_MEMO_LEN
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            // スクロール位置表示は全画面で出さない
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("edit.pack"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                navigationToolbar
            }
        }
        .sheet(isPresented: $isPresentingShare, onDismiss: cleanupShareResource) {
            if let shareURL {
                // 共有　パック保存
                ActivityView(activityItems: [shareURL])
            }
        }
        // 初回公開時：作者ニックネーム入力（プライバシー注意も併記）
        .alert("publish.nickname.title", isPresented: $showNicknamePrompt) {
            TextField("publish.nickname.placeholder", text: $nicknameDraft)
            Button("publish.nickname.save.publish") { confirmNickname(useDraft: true) }
            Button("publish.nickname.anonymous.publish") { confirmNickname(useDraft: false) }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("publish.privacy.notice")
        }
        // 2回目以降の公開時：プライバシー注意つき確認
        .alert("publish.confirm.title", isPresented: $showPublishConfirm) {
            Button("publish.action") { Task { await performPublish() } }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("publish.privacy.notice")
        }
        // 公開結果
        .alert("publish.save", isPresented: $showPublishResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishResultMessage)
        }
        // 公開中は全画面プログレスを重ねて操作を遮断する
        .overlay {
            if isPublishing {
                publishingOverlay
            }
        }
        .onAppear {
            // === Fix 7: lifecycle 不均衡対策 ===
            // 二重 onAppear（NavigationStack のプッシュ復帰時など）を考慮し、
            // 未開始のときだけ groupingBegin する。
            // 通常の編集開始時はここで Undo グループが 1 つ開かれ、
            // 編集内容全体が「1 つの Undo」として扱われる。
            beginUndoGroupingIfNeeded()
            focusNameIfEmpty()
        }
        .onDisappear() {
            // === Fix 7: lifecycle 不均衡対策 ===
            // 末尾のスペースと改行を除去（編集内容の正規化）
            pack.name = pack.name.trimTrailSpacesAndNewlines
            pack.memo = pack.memo.trimTrailSpacesAndNewlines
            // begin したときだけ end する。これにより onAppear なしの onDisappear や
            // 二重 onDisappear でも transactionDepth が壊れない。
            endUndoGroupingIfNeeded()
        }
    }

    /// === Fix 7: Undo グループの安全な開始 ===
    /// `isUndoGroupingActive` フラグで再入を防止する。既に開いていれば何もしない。
    /// onAppear が複数回呼ばれた場合でも、グルーピングは 1 回だけ開始される。
    private func beginUndoGroupingIfNeeded() {
        guard !isUndoGroupingActive else { return }
        modelContext.undoManager?.groupingBegin()
        isUndoGroupingActive = true
    }

    /// === Fix 7: Undo グループの安全な終了 ===
    /// `isUndoGroupingActive` が立っているときだけ end を呼ぶ。
    /// これにより、onAppear なしの onDisappear、または onDisappear の二重呼び出しで
    /// `UndoStackService.transactionDepth` が負方向に進むのを防ぐ。
    private func endUndoGroupingIfNeeded() {
        guard isUndoGroupingActive else { return }
        modelContext.undoManager?.groupingEnd()
        isUndoGroupingActive = false
    }

    private var nameFocusBinding: Binding<Bool> {
        Binding(
            get: { nameIsFocused },
            set: { nameIsFocused = $0 }
        )
    }

    private var memoFocusBinding: Binding<Bool> {
        Binding(
            get: { memoIsFocused },
            set: { memoIsFocused = $0 }
        )
    }

    private func focusNameIfEmpty() {
        guard pack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // シート表示直後はTextEditorの生成が遅れるため、表示確定後にNameへフォーカスする
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if pack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nameIsFocused = true
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            compactActionButton(title: LocalizedStringKey(allItemsChecked ? "check.off" : "check"),
                                fixedWidth: 108,
                                twoLineTitle: checkTwoLineTitle,
                                tint: .accentColor,
                                action: startCheckToggle) {
                ZStack {
                    Image(systemName: "case")
                        .imageScale(.large)
                        .symbolRenderingMode(.hierarchical)
                    if allItemsChecked {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                            .padding(.top, 4)
                    }
                }
            }
            .overlay(alignment: .center) {
                if isTogglingCheck {
                    // 起動直後など処理が重い瞬間はスピナーを表示して進捗を見せる
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .disabled(isTogglingCheck) // 進行中はタップを無効化

            compactActionButton(title: "copy",
                                systemImage: "plus.square.on.square",
                                tint: .accentColor) {
                pack.duplicate()
            }

            compactActionButton(title: "share",
                                systemImage: "square.and.arrow.up",
                                tint: .accentColor,
                                action: exportPack)

            Spacer(minLength: 0)

            compactActionButton(title: "delete",
                                systemImage: "trash",
                                tint: .red) {
                // シートを強制的に閉じてから削除処理へ進める
                dismiss()
                // Packを削除する
                pack.delete()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .buttonStyle(.borderless)
    }

    private func compactActionButton(title: LocalizedStringKey,
                                     systemImage: String,
                                     tint: Color,
                                     action: @escaping () -> Void) -> some View {
        compactActionButton(title: title, tint: tint, action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func compactActionButton<Icon: View>(title: LocalizedStringKey,
                                                 fixedWidth: CGFloat? = nil,
                                                 twoLineTitle: (LocalizedStringKey, LocalizedStringKey)? = nil,
                                                 tint: Color,
                                                 action: @escaping () -> Void,
                                                 @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon()
                if let twoLineTitle {
                    VStack(spacing: 0) {
                        Text(twoLineTitle.0)
                        Text(twoLineTitle.1)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                } else {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minWidth: 58)
            .frame(width: fixedWidth)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .tint(tint)
    }

    private var checkTwoLineTitle: (LocalizedStringKey, LocalizedStringKey)? {
        if fontScale == .large || fontScale == .xLarge {
            return ("check.label", allItemsChecked ? "check.off.state" : "check.on.state")
        }
        return nil
    }

    private func editCard<Content: View>(title: LocalizedStringKey,
                                         minHeight: CGFloat,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
                .frame(minHeight: minHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                // 閉じる
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            // 公開保存（旧チャッピーボタンの位置）＋ 右にヘルプ(?)
            HStack(spacing: 8) {
                Button {
                    startPublish()
                } label: {
                    HStack {
                        // iOS26 などで追加されたシンボルが古いOSで空白にならないよう代替を用意
                        Image(systemName: "square.and.arrow.up.on.square", fallback: "square.and.arrow.up")
                            .symbolRenderingMode(.hierarchical)
                        if isPublishing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("publish.save")
                                .font(.body.weight(.regular))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isPublishing)

                Button {
                    showPublishHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .imageScale(.large)
                        .symbolRenderingMode(.hierarchical)
                }
                .sheet(isPresented: $showPublishHelp) {
                    publishHelpSheet
                }
            }
        }
    }

    /// 公開中の全画面プログレス
    private var publishingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("publish.publishing")
                    .font(.callout.weight(.semibold))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        // カバーがタップを受けて背面の操作を遮断する
        .contentShape(Rectangle())
    }

    /// 公開保存のヘルプ（シート表示）
    private var publishHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("publish.help.line1")
                    Text("publish.help.line2")
                    Text("publish.help.line3")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("publish.help.caution")
                    }
                    .foregroundStyle(.red)
                }
                .font(.callout)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("publish.save"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showPublishHelp = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .appFontScale(fontScale)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// チェック・トグルが遅延する場合があるのでプログレス付きで開始する
    ///  起動初期にDB遅延が発生して無反応に見えるためタスク化して終了を待つ
    private func startCheckToggle() {
        // 連打による状態不整合を避けるため、進行中は何もしない
        if isTogglingCheck { return }
        isTogglingCheck = true

        Task { @MainActor in
            defer {
                // 処理完了後にスピナーを消す
                isTogglingCheck = false
            }
            // 従来どおり、現在の全チェック状態からON/OFFを切り替える
            updateChecks(checked: !allItemsChecked)
        }
    }

    /// 配下の全item.checkを指定状態へ揃える。.stockは設定に応じて連動する
    private func updateChecks(checked: Bool) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        let items = pack.child.flatMap { $0.child }
        for item in items {
            if checked {
                // OFF --> ON
                item.check = (0 < item.need)
                // チェックと在庫数を連動させる
                if linkCheckWithStock {
                    item.stock = item.need
                }
            }else{
                // ON --> OFF
                item.check = false
                if linkCheckOffWithZero {
                    // チェック解除時の在庫クリアは新フラグで管理
                    item.stock = 0
                }
            }
        }
    }
    
    // MARK: - 公開保存

    /// 公開保存ボタン。ニックネーム未設定なら先に入力させ、設定済みなら確認へ進む
    private func startPublish() {
        if isPublishing { return }
        if authorNicknameConfigured {
            showPublishConfirm = true
        } else {
            nicknameDraft = authorNickname
            showNicknamePrompt = true
        }
    }

    /// ニックネーム入力の確定。useDraft=false は「匿名のまま公開」
    private func confirmNickname(useDraft: Bool) {
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        authorNickname = useDraft ? trimmed : ""
        authorNicknameConfigured = true
        Task { await performPublish() }
    }

    /// 実際に公開保存する。サーバーで Pack ID（sourcePackId）により上書きされる
    @MainActor
    private func performPublish() async {
        if isPublishing { return }
        isPublishing = true
        defer { isPublishing = false }
        do {
            let userId = creditStore.regenerateUserIdIfNeeded()
            // 認証必須エンドポイントのため、トークン未取得ならまず credit/check で発行する
            // 発行に失敗した場合は missingAuthToken に丸めず、実エラーをそのまま表示する
            if AzukiApi.shared.hasValidAccessToken() == false {
                _ = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
            }
            // 現在のニックネームをサーバーへ反映（空文字＝匿名）
            try await AzukiApi.shared.updateNickname(userId: userId, nickname: authorNickname)

            // 末尾の空白・改行を正規化してから公開内容を組み立てる
            pack.name = pack.name.trimTrailSpacesAndNewlines
            pack.memo = pack.memo.trimTrailSpacesAndNewlines

            let dto = pack.exportRepresentation()
            let itemCount = pack.child.reduce(0) { $0 + $1.child.count }
            // アプリ対応言語(ja/en)ではなくデバイス本来のロケールを登録する
            let locale = devicePreferredLanguageCode()

            _ = try await AzukiApi.shared.publishPack(
                userId: userId,
                sourcePackId: pack.id,
                dto: dto,
                locale: locale,
                searchText: buildPublishSearchText(),
                groupCount: pack.child.count,
                itemCount: itemCount,
                totalWeight: pack.needWeight
            )
            GALogger.log(.feature_use(name: "public_pack", source: "pack_edit", detail: "publish"))
            GALogger.log(.public_pack_result(action: "publish", isSuccess: true, itemCount: itemCount,
                                             errorDomain: nil, errorCode: nil, message: nil))
            publishResultMessage = String(localized: "publish.success")
        } catch let apiError as AzukiAPIError {
            let info = publicPackErrorInfo(apiError)
            GALogger.log(.public_pack_result(action: "publish", isSuccess: false, itemCount: nil,
                                             errorDomain: info.domain, errorCode: info.code, message: info.message))
            publishResultMessage = apiError.errorDescription
                ?? String(localized: "network.seems.down.please.try.again")
        } catch {
            let info = publicPackErrorInfo(error)
            GALogger.log(.public_pack_result(action: "publish", isSuccess: false, itemCount: nil,
                                             errorDomain: info.domain, errorCode: info.code, message: info.message))
            publishResultMessage = String(localized: "network.seems.down.please.try.again")
        }
        showPublishResult = true
    }

    /// 検索用テキスト（name・memo・グループ名・アイテム名を連結）
    private func buildPublishSearchText() -> String {
        var parts: [String] = [pack.name, pack.memo]
        for group in pack.child {
            parts.append(group.name)
            parts.append(group.memo)
            for item in group.child {
                parts.append(item.name)
                parts.append(item.memo)
            }
        }
        return parts.filter { $0.isEmpty == false }.joined(separator: " ")
    }

    /// Packを.packlinファイルにして共有(Export)する
    private func exportPack() {
        do {
            cleanupShareResource()

            let dto = pack.exportRepresentation()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(dto)
            // ファイル名を使用可能文字に制限する
            let fileName = sanitizedFileName(from: pack.name.isEmpty
                                             ? pack.id : pack.name )
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
                .appendingPathExtension(PACK_FILE_EXTENSION)

            try data.write(to: fileURL, options: [.atomic])

            shareURL = fileURL
            isPresentingShare = true
        } catch {
            // パック書き出し失敗をAnalyticsへ送り、共有導線の問題分析に使う
            logError(error, domain: "pack_export", message: "パック書き出し失敗")
        }
    }
    /// 一時共有ファイルを削除する
    private func cleanupShareResource() {
        defer {
            shareURL = nil
            isPresentingShare = false
        }

        guard let shareURL else { return }
        try? FileManager.default.removeItem(at: shareURL)
    }
    /// ファイル名を使用可能文字に制限する
    ///    shortUUIDをURLセーフにしたが、さらに念の為
    private func sanitizedFileName(from name: String) -> String {
        let base = "Pack_" + name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "\\/:?%*|\"<>\n")
        let components = base.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
        return sanitized.isEmpty ? "Pack_unnamed" : sanitized
    }
}
