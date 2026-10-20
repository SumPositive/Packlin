//
//  TagManageSheet.swift
//  PackList
//
//  パックのタグを一覧で編集するシート（名前の変更・削除）
//  アイテム詳細のタグ欄の「編集」と、アイテム縦覧のタグ一覧の「編集」から開く
//

import SwiftUI
import SwiftData

struct TagManageSheet: View {
    let pack: M1Pack

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var history: UndoStackService
    @Environment(\.dismiss) private var dismiss

    /// 名前を変える画面へ進んでいるタグ（空なら一覧）
    @State private var path: [String] = []
    /// シートの今の高さ
    @State private var detent: PresentationDetent = .medium

    /// 名前の変更中は、ラージならそのまま、それ以外はキーボード分だけ低くしてシートの上端を動かさない高さ1つにする
    private var detents: Set<PresentationDetent> {
        guard !path.isEmpty else { return [.medium, .large] }
        return detent == .large ? [.large] : [.custom(TagRenameDetent.self)]
    }

    /// 並びは縦覧のタグ一覧と同じ指定順
    private var tags: [String] { pack.tagsInManualOrder }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if tags.isEmpty {
                    Text("tag.empty")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(tags, id: \.self) { tag in
                            // 名前の変更は次の画面で行う（入力欄付きアラートはキーボード表示中のキャンセルが2回押しになるため）
                            NavigationLink(value: tag) {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    // このタグが付いているアイテム数
                                    Text(verbatim: "\(pack.tagItemCounts[tag] ?? 0)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        // 説明は一覧の上の余白に置く（下に置くと、一覧が長いときに見えない）
                        Text("tag.manage.footer")
                            .textCase(nil)
                    }
                }
            }
            .navigationTitle(Text("tag.manage.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 閉じる（ほかのシートと同じ下向きの山型）
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .navigationDestination(for: String.self) { tag in
                TagRenameView(oldTag: tag,
                              itemCount: pack.tagItemCounts[tag] ?? 0,
                              onRename: { newTag in rename(tag, to: newTag) },
                              onDelete: { remove(tag) })
            }
        }
        // 中くらいの高さで開き、ハンドルや一覧を上へスクロールすると大きく広がる（閉じるのは下へスワイプ）
        .presentationDetents(detents, selection: $detent)
        .onAppear {
            KeyboardHeightTracker.start()
        }
        // 名前の変更へ進む／一覧へ戻るときに、選んでいる高さを切り替える
        .onChange(of: path.isEmpty) { _, isList in
            if isList {
                if detent != .large { detent = .medium }
            } else if detent != .large {
                detent = .custom(TagRenameDetent.self)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
    }

    private func rename(_ oldTag: String, to newTag: String) {
        guard !newTag.isEmpty, newTag != oldTag else { return }
        GALogger.log(.operation(name: "rename", target: "tag", source: "tag_manage_sheet", detail: nil, count: nil))
        history.perform(context: modelContext) {
            pack.renameTag(oldTag, to: newTag)
        }
    }

    private func remove(_ tag: String) {
        GALogger.log(.operation(name: "delete", target: "tag", source: "tag_manage_sheet", detail: nil, count: nil))
        history.perform(context: modelContext) {
            pack.removeTag(tag)
        }
    }
}

/// タグの名前を変える画面。戻ると取り消し、「変更」で確定して戻る
private struct TagRenameView: View {
    let oldTag: String
    /// このタグが付いているアイテム数（削除の確認に出す）
    let itemCount: Int
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var isConfirmingDelete = false

    private var trimmedNewName: String {
        String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(APP_MAX_TAG_LEN))
    }

    private var canRename: Bool {
        !trimmedNewName.isEmpty && trimmedNewName != oldTag
    }

    var body: some View {
        List {
            Section {
                TextField(LocalizedStringKey("tags"), text: $newName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(commit)
            } footer: {
                // 同じタグのアイテムもまとめて変わること、既にある名前ならまとまること
                Text("tag.rename.message")
            }
            // このタグを削除（このパックのすべてのアイテムから外す）
            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    // アイコンも文字も白にする（アイコンはアプリの色付けで青くなるため明示する）
                    Label {
                        Text("tag.delete.this")
                    } icon: {
                        Image(systemName: "trash")
                    }
                    .foregroundStyle(.white)
                }
                // 赤い背景・白い文字の、中身ぴったりの小さいボタンを中央に置く（一覧の行の見た目にはしない）
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text("tag.rename.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("tag.rename.button", action: commit)
                    .disabled(!canRename)
            }
        }
        // 開いた時点ではフォーカスを入れない（キーボードは入力欄をタップしたときだけ出す）
        .onAppear {
            newName = oldTag
        }
        .alert("tag.delete.confirm.title", isPresented: $isConfirmingDelete) {
            Button("delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "tag.delete.confirm.message"), oldTag, itemCount))
        }
    }

    private func commit() {
        guard canRename else { return }
        onRename(trimmedNewName)
        dismiss()
    }
}

/// 名前の変更中のシートの高さ：ミドルからキーボードの高さを引いて、キーボードが出てもシートの上端を動かさない
/// 入力欄まで隠れそうなほど低くなるときだけ、最低限の高さを残してシートを持ち上げる
private struct TagRenameDetent: CustomPresentationDetent {
    /// ナビゲーションバー・入力欄・説明の1行目が見える高さ
    private static let minimumHeight: CGFloat = 200

    static func height(in context: Context) -> CGFloat? {
        let keyboard = KeyboardHeightTracker.height
        // キーボードが出ると使える高さがその分減るので、足し戻してキーボードが無いときのミドルを求める
        let medium = (context.maxDetentValue + keyboard) / 2
        return max(medium - keyboard, minimumHeight)
    }
}

/// キーボードの高さを覚えておく（シートの高さの計算から読むため）
private enum KeyboardHeightTracker {
    nonisolated(unsafe) static var height: CGFloat = 0
    nonisolated(unsafe) private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                                          object: nil, queue: .main) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // 画面の下端から上に出ている分だけをキーボードの高さとする（隠れるときは 0）
            let screenHeight = UIScreen.main.bounds.height
            height = max(screenHeight - frame.minY, 0)
        }
    }
}
