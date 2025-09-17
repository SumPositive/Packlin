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
    let pack: M1Pack
    let onEdit: (M1Pack, CGPoint) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    
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
                    GeometryReader { geo in
                        rowFrame = geo.frame(in: .global)
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("packList"))
                        .onEnded { value in
                            let translation = value.translation
                            guard abs(translation.width) < 8, abs(translation.height) < 8 else { return }
                            let po = CGPoint(x: rowFrame.width / 2.0,
                                             y: rowFrame.minY + value.location.y)
                            onEdit(pack, po) //.locationはRow内の相対座標
                        }
                )
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

}

