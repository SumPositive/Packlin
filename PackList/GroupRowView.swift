//
//  GroupRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct GroupRowView: View {
    @Environment(\.modelContext) private var modelContext
    let group: M2Group
    let isHeader: Bool

    @State private var editingGroup: M2Group?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom

    private let rowHeight: CGFloat = 44

    init(group: M2Group, isHeader: Bool) {
        self.group = group
        self.isHeader = isHeader
    }

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check }
    }

    var body: some View {
        Group {
            HStack(spacing: 0) {
                Image(systemName: allItemsChecked ? "checkmark.rectangle" : "rectangle")
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name.isEmpty ? "New Group" : group.name)
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(group.name.isEmpty ? .secondary : COLOR_NAME)
                    
                    if !group.memo.isEmpty {
                        Text(group.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.leading, 25)
                    }
                    if DEBUG_SHOW_ORDER_ID {
                        Text("group (\(group.order)) [\(group.id)]")
                    }
                    
                    HStack {
                        Spacer() // 右寄せにするため
                        if 0 < group.stockWeight {
                            Text("\(group.stockWeight)g／\(group.needWeight)g")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.trailing, 4)
                        }
                        
                        if isHeader {
                            Button(action: addItem) {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: rowHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .contentShape(Rectangle())
            .swipeActions(edge: .trailing) {
                Button("Cut") {
                    copyToClipboard()
                    deleteGroup()
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
                .disabled(RowClipboard.group == nil && RowClipboard.item == nil)
                .tint(.orange)

                Button("Duplicate") {
                    duplicateGroup()
                }
                .tint(.green)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { oldValue, newValue in
                            frame = newValue
                        }
                }
            )
            .onTapGesture {
                arrowEdge = arrowEdge(for: frame)
                editingGroup = group
            }
            .popover(item: $editingGroup, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { group in
                EditGroupView(group: group)
                    .presentationCompactAdaptation(.none)
                    .background(Color.primary.opacity(0.2))
            }
        }
    }

    private func addItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        let newItem = M3Item(name: "", order: group.nextItemOrder(), parent: group)
        modelContext.insert(newItem)
        withAnimation {
            group.child.append(newItem)
            group.normalizeItemOrder()
        }
    }
    
    private func deleteGroup() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        for item in group.child {
            modelContext.delete(item)
        }
        if let parent = group.parent,
           let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.remove(at: index)
            parent.normalizeGroupOrder()
        }
        modelContext.delete(group)
    }

    private func duplicateGroup() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        guard let parentTitle = group.parent else { return }
        let newGroup = M2Group(name: group.name, memo: group.memo, order: parentTitle.nextGroupOrder(), parent: parentTitle)
        modelContext.insert(newGroup)
        withAnimation {
            if let index = parentTitle.child.firstIndex(where: { $0.id == group.id }) {
                parentTitle.child.insert(newGroup, at: index + 1)
            } else {
                parentTitle.child.append(newGroup)
            }
            parentTitle.normalizeGroupOrder()
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }

    private func copyToClipboard() {
        RowClipboard.clear()
        RowClipboard.group = cloneGroup(group)
    }

    private func pasteFromClipboard() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        if let clip = RowClipboard.group, let parent = group.parent {
            // GroupRowを現在行にペーストする、現在行は下になる
            let newGroup = cloneGroup(clip, parent: parent)
            newGroup.order = group.order
            modelContext.insert(newGroup)
            withAnimation {
                // 現在行(index)を求めその行に追加する
                if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
                    // index位置に追加
                    parent.child.insert(newGroup, at: index)
                } else {
                    // 末尾に追加
                    parent.child.append(newGroup)
                }
                parent.normalizeGroupOrder()
            }
        }
        else if let clip = RowClipboard.item {
            // ItemRowをGroupの最上行に挿入する
            let newItem = cloneItem(clip, parent: group)
            newItem.order = -1 // 最上行  group.nextItemOrder()
            modelContext.insert(newItem)
            withAnimation {
                group.child.insert(newItem, at: 0)
                group.normalizeItemOrder()
            }
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

    private func arrowEdge(for frame: CGRect?) -> Edge {
        guard let frame = frame else { return .bottom }
        let screenHeight = UIScreen.main.bounds.height
        let topSpace = frame.minY
        let bottomSpace = screenHeight - frame.maxY
        return bottomSpace > topSpace ? .top : .bottom
    }
}

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var group: M2Group
    @StateObject private var keyboardObserver = KeyboardObserver()
    @FocusState private var focusedField: Field?
    @State private var fieldFrames: [Field: CGRect] = [:]
    @State private var containerFrame: CGRect = .zero

    private enum Field: Hashable {
        case name
        case memo
    }

    private struct FieldFramePreferenceKey: PreferenceKey {
        static var defaultValue: [Field: CGRect] = [:]

        static func reduce(value: inout [Field: CGRect], nextValue: () -> [Field: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    private struct ContainerFramePreferenceKey: PreferenceKey {
        static var defaultValue: CGRect = .zero

        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    private var keyboardOffset: CGFloat {
        guard keyboardObserver.keyboardHeight > 0,
              let focusedField,
              let fieldFrame = fieldFrames[focusedField],
              containerFrame != .zero else {
            return 0
        }

        let keyboardTop = UIScreen.main.bounds.height - keyboardObserver.keyboardHeight
        let safeMargin: CGFloat = 16
        let overlap = fieldFrame.maxY + safeMargin - keyboardTop
        guard overlap > 0 else { return 0 }

        let availableOffset = max(0, fieldFrame.minY - containerFrame.minY)
        return min(overlap, availableOffset)
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom
            let bottomPadding = max(0, keyboardObserver.keyboardHeight - bottomInset)

            ScrollView {
                VStack {
                    HStack {
                        Text("名称:")
                            .font(.caption)
                            .padding(4)
                        TextEditor(text: $group.name)
                            .onChange(of: group.name) { newValue, oldValue in
                                if APP_MAX_NAME_LEN < newValue.count {
                                    group.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                                }
                            }
                            .focused($focusedField, equals: .name)
                            .frame(width: 260, height: 80)
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.name: proxy.frame(in: .global)])
                                }
                            )
                    }
                    HStack {
                        Text("メモ:")
                            .font(.caption)
                            .padding(4)
                        TextEditor(text: $group.memo)
                            .onChange(of: group.memo) { newValue, oldValue in
                                if APP_MAX_MEMO_LEN < newValue.count {
                                    group.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                                }
                            }
                            .focused($focusedField, equals: .memo)
                            .frame(width: 260, height: 80)
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.memo: proxy.frame(in: .global)])
                                }
                            )
                    }
                }
                .padding()
                .frame(minWidth: 300)
            }
            .padding(.bottom, bottomPadding)
            .offset(y: -keyboardOffset)
            .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
            .animation(.easeOut(duration: 0.25), value: focusedField)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContainerFramePreferenceKey.self,
                                            value: proxy.frame(in: .global))
                }
            )
        }
        .onPreferenceChange(FieldFramePreferenceKey.self) { frames in
            fieldFrames = frames
        }
        .onPreferenceChange(ContainerFramePreferenceKey.self) { frame in
            containerFrame = frame
        }
        .onAppear {
            modelContext.undoManager?.beginUndoGrouping()
            if group.name.isEmpty {
                focusedField = .name
            }
        }
        .onDisappear {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            //try? modelContext.save() // Undoスタックがクリアされる
        }
    }
}

