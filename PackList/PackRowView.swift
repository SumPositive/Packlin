//
//  PackRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct PackRowView: View {
    @Environment(\.modelContext) private var modelContext
    let pack: M1Pack
    
    @State private var editingPack: M1Pack?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    @State private var keyboardHeight: CGFloat = 0

    private let keyboardHeightObserver = KeyboardHeightObserver()
   
    private let rowHeight: CGFloat = 44

    init(pack: M1Pack) {
        self.pack = pack
    }

    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check }
    }


    var body: some View {
        Group {
            HStack(spacing: 0) {
                Image(systemName: allItemsChecked ? "checkmark.message" : "message")
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(pack.name.isEmpty ? "New Pack" : pack.name)
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(pack.name.isEmpty ? .secondary : COLOR_NAME)
                    
                    if !pack.memo.isEmpty {
                        Text(pack.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.leading, 25)
                    }
                    if DEBUG_SHOW_ORDER_ID {
                        Text("pack (\(pack.order)) [\(pack.id)]")
                    }
                    
                    HStack {
                        Spacer() // 右寄せにするため
                        if 0 < pack.stockWeight {
                            Text("\(pack.stockWeight)g／\(pack.needWeight)g")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.trailing, 8)
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: rowHeight)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            let newFrame = proxy.frame(in: .global)
                            frame = newFrame
                            arrowEdge = arrowEdge(for: newFrame, keyboardHeight: keyboardHeight)
                        }
                        .onChange(of: proxy.frame(in: .global)) { oldValue, newValue in
                            frame = newValue
                            arrowEdge = arrowEdge(for: newValue, keyboardHeight: keyboardHeight)
                        }
                }
            )
            .onTapGesture {
                arrowEdge = arrowEdge(for: frame, keyboardHeight: keyboardHeight)
                editingPack = pack
            }
            .popover(item: $editingPack, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { title in
                EditPackView(pack: title, keyboardHeight: keyboardHeight)
                    .presentationCompactAdaptation(.none)
                    .background(Color.primary.opacity(0.2))
            }
            .onReceive(keyboardHeightObserver.willShow) { notification in
                let height = keyboardHeightObserver.height(from: notification)
                keyboardHeight = height
                arrowEdge = arrowEdge(for: frame, keyboardHeight: height)
            }
            .onReceive(keyboardHeightObserver.willHide) { _ in
                keyboardHeight = 0
                arrowEdge = arrowEdge(for: frame, keyboardHeight: 0)
            }
            .swipeActions(edge: .trailing) {
                Button("Cut") {
                    copyToClipboard()
                    deletePack()
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                Button("Copy") {
                    copyToClipboard()
                }
                .tint(.cyan)
                
                Button("Paste") {
                    pasteFromClipboard()
                }
                .disabled(RowClipboard.pack == nil)
                .tint(.orange)
                
                Button("Duplicate") {
                    duplicatePack()
                }
                .tint(.green)
            }
        }
    }

    private func deletePack() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        for group in pack.child {
            deleteGroup(group)
        }
        modelContext.delete(pack)
        let descriptor = FetchDescriptor<M1Pack>()
        if let packs = try? modelContext.fetch(descriptor) {
            M1Pack.normalizePackOrder(packs)
        }
    }

    private func deleteGroup(_ group: M2Group) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func duplicatePack() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        let descriptor = FetchDescriptor<M1Pack>()
        let packs = (try? modelContext.fetch(descriptor)) ?? []
        let newOrder = M1Pack.nextPackOrder(packs)
        let newTitle = M1Pack(name: pack.name, memo: pack.memo, createdAt: pack.createdAt.addingTimeInterval(-0.001), order: newOrder)
        modelContext.insert(newTitle)
        for group in pack.child {
            copyGroup(group, to: newTitle)
        }
    }

    private func copyToClipboard() {
        RowClipboard.group = nil
        RowClipboard.item = nil
        RowClipboard.pack = clonePack(pack)
    }

    private func pasteFromClipboard() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        if let template = RowClipboard.pack {
            // PackRowを現在行にペーストする、現在行は下になる
            let newPack = clonePack(template)
            newPack.order = pack.order
            modelContext.insert(newPack)
            // 現在行(index)を求めその行に追加する
            let descriptor = FetchDescriptor<M1Pack>()
            var packs = (try? modelContext.fetch(descriptor)) ?? []
            if let index = packs.firstIndex(where: { $0.id == pack.id }) {
                // index位置に追加
                packs.insert(newPack, at: index)
            } else {
                // 末尾に追加
                packs.append(newPack)
            }
            M1Pack.normalizePackOrder(packs)
        }
        else if let clip = RowClipboard.group {
            // GroupRowをPackの最上行に挿入する
            let newGroup = cloneGroup(clip, parent: pack)
            newGroup.order = -1 // 最上行
            modelContext.insert(newGroup)
            withAnimation {
                pack.child.insert(newGroup, at: 0)
                pack.normalizeGroupOrder()
            }
        }
    }

    private func copyGroup(_ group: M2Group, to parent: M1Pack) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        let newGroup = M2Group(name: group.name, memo: group.memo, order: parent.nextGroupOrder(), parent: parent)
        modelContext.insert(newGroup)
        withAnimation {
            if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
                parent.child.insert(newGroup, at: index + 1)
            } else {
                parent.child.append(newGroup)
            }
            parent.normalizeGroupOrder()
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }

    private func copyItem(_ item: M3Item, to parent: M2Group) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        let newItem = M3Item(name: item.name, memo: item.memo, stock: item.stock, need: item.need, weight: item.weight, order: parent.nextItemOrder(), parent: parent)
        modelContext.insert(newItem)
        parent.child.append(newItem)
        parent.normalizeItemOrder()
    }

    private func arrowEdge(for frame: CGRect?, keyboardHeight: CGFloat) -> Edge {
        guard let frame = frame else { return .bottom }
        let screenHeight = UIScreen.main.bounds.height
        let topSpace = frame.minY
        let bottomSpace = screenHeight - keyboardHeight - frame.maxY
        return bottomSpace > topSpace ? .top : .bottom
    }
}

struct KeyboardHeightObserver {
    let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
    let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

    func height(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        return max(0, frame.height)
    }
}

struct EditPackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var pack: M1Pack
    @FocusState private var nameIsFocused: Bool
    let keyboardHeight: CGFloat

    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("名称:")
                        .font(.caption)
                        .padding(4)
                    TextEditor(text: $pack.name)
                        .onChange(of: pack.name) { newValue, oldValue in
                            if APP_MAX_NAME_LEN < newValue.count {
                                pack.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                            }
                        }
                        .focused($nameIsFocused) // フォーカス状態とバインド
                        .frame(width: 260, height: 80)
                        .padding(4)
                }
                HStack {
                    Text("メモ:")
                        .font(.caption)
                        .padding(4)
                    TextEditor(text: $pack.memo)
                        .onChange(of: pack.memo) { newValue, oldValue in
                            if APP_MAX_MEMO_LEN < newValue.count {
                                pack.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                            }
                        }
                        .frame(width: 260, height: 80)
                        .padding(4)
                }
            }
            .padding()
            .padding(.bottom, keyboardHeight)
        }
        .frame(minWidth: 300, maxHeight: 300)
        .onAppear {
            modelContext.undoManager?.beginUndoGrouping()
            if pack.name.isEmpty {
                nameIsFocused = true
            }
        }
        .onDisappear() {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            //try? modelContext.save() // Undoスタックがクリアされる
        }
    }
}

