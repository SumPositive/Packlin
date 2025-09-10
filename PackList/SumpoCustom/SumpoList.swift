//
//  SumpoList.swift
//  PackList
//
//  Created by Sum Positive on 2025/09/10.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - モデル

struct TreeNode<D>: Identifiable, Hashable where D: Hashable {
    let id = UUID()
    var data: D
    var isExpanded: Bool = true
    var children: [TreeNode<D>] = []
}

struct NodePath: Hashable, Codable {
    var indices: [Int]
    var parent: NodePath? { indices.count > 1 ? NodePath(indices: Array(indices.dropLast())) : nil }
    var lastIndex: Int { indices.last ?? 0 }
    var depth: Int { max(indices.count - 1, 0) }
}

// MARK: - VM（親跨ぎDnD）

final class PinnedTreeViewModel<D>: ObservableObject where D: Hashable {
    @Published var roots: [TreeNode<D>]
    init(_ roots: [TreeNode<D>]) { self.roots = roots }
    
    func node(at p: NodePath) -> TreeNode<D>? {
        var cur = roots
        for (lvl, i) in p.indices.enumerated() {
            guard cur.indices.contains(i) else { return nil }
            if lvl == p.indices.count - 1 { return cur[i] }
            cur = cur[i].children
        }
        return nil
    }
    func setNode(_ new: TreeNode<D>, at p: NodePath) {
        func setAt(_ level: Int, _ arr: inout [TreeNode<D>]) {
            let i = p.indices[level]
            if level == p.indices.count - 1 { arr[i] = new }
            else { setAt(level + 1, &arr[i].children) }
        }
        setAt(0, &roots); objectWillChange.send()
    }
    
    func children(of parent: NodePath?) -> [TreeNode<D>] {
        guard let parent else { return roots }
        var cur = roots
        for (lvl, i) in parent.indices.enumerated() {
            guard cur.indices.contains(i) else { return [] }
            if lvl == parent.indices.count - 1 { return cur[i].children }
            cur = cur[i].children
        }
        return []
    }
    func setChildren(_ new: [TreeNode<D>], of parent: NodePath?) {
        if parent == nil { roots = new; objectWillChange.send(); return }
        func setAt(_ level: Int, _ arr: inout [TreeNode<D>]) {
            let i = parent!.indices[level]
            if level == parent!.indices.count - 1 { arr[i].children = new }
            else { setAt(level + 1, &arr[i].children) }
        }
        setAt(0, &roots); objectWillChange.send()
    }
    
    func toggleExpand(_ p: NodePath) {
        guard var n = node(at: p) else { return }
        n.isExpanded.toggle()
        setNode(n, at: p)
    }
    func addChild(_ child: TreeNode<D>, to parent: NodePath?) {
        var arr = children(of: parent); arr.append(child); setChildren(arr, of: parent)
    }
    func delete(at p: NodePath) {
        if let par = p.parent {
            var arr = children(of: par)
            guard arr.indices.contains(p.lastIndex) else { return }
            arr.remove(at: p.lastIndex); setChildren(arr, of: par)
        } else {
            guard roots.indices.contains(p.lastIndex) else { return }
            roots.remove(at: p.lastIndex); objectWillChange.send()
        }
    }
    
    // 親を跨ぐ移動（同depth限定）
    func moveNode(from source: NodePath, to targetParent: NodePath?, at targetIndex: Int) {
        let expectedDepth = (targetParent?.depth ?? -1) + 1
        guard source.depth == expectedDepth else { return }
        
        // 取り出し
        let moving: TreeNode<D>
        if let sp = source.parent {
            var arr = children(of: sp)
            guard arr.indices.contains(source.lastIndex) else { return }
            moving = arr.remove(at: source.lastIndex)
            setChildren(arr, of: sp)
        } else {
            guard roots.indices.contains(source.lastIndex) else { return }
            moving = roots.remove(at: source.lastIndex)
            objectWillChange.send()
        }
        
        // 挿入
        var dst = children(of: targetParent)
        var idx = min(max(targetIndex, 0), dst.count)
        if source.parent == targetParent, targetIndex > source.lastIndex { idx -= 1 }
        dst.insert(moving, at: idx)
        setChildren(dst, of: targetParent)
    }
}

// MARK: - DnD payload

private let nodeUTType = UTType(exportedAs: "com.azukid.nodepath.json")
struct DragPayload: Codable, Hashable { let path: NodePath }

// MARK: - 型消去ヘルパ（AnyViewで推論エラー対策）

@inline(__always) func erase<V: View>(_ v: V) -> AnyView { AnyView(v) }

// MARK: - ヘッダ行（ピン留め表示）

struct HeaderRow<D>: View where D: Hashable {
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let title: AnyView
    let subtitle: AnyView?
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(depth) * 16)
            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.subheadline).frame(width: 14)
                    .onTapGesture { onToggle() }
            } else {
                Color.clear.frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(depth == 0 ? .headline : .subheadline.weight(.semibold))
                if let subtitle { subtitle.font(.caption).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if hasChildren { onToggle() } }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .background(.ultraThinMaterial) // ヘッダ視認性を上げる
    }
}

// MARK: - ドロップ位置種別

enum DropPosition { case on, before, after }

// MARK: - DropDelegate（ScrollView/LazyVStack用）

struct NodeDropDelegate<D>: DropDelegate where D: Hashable {
    @ObservedObject var vm: PinnedTreeViewModel<D>
    let targetPath: NodePath
    let position: DropPosition
    let isHeader: Bool
    @Binding var hover: Bool
    
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [nodeUTType]) }
    func dropEntered(info: DropInfo) { hover = true }
    func dropExited(info: DropInfo) { hover = false }
    func performDrop(info: DropInfo) -> Bool {
        hover = false
        guard let item = info.itemProviders(for: [nodeUTType]).first else { return false }
        var ok = false
        _ = item.loadDataRepresentation(forTypeIdentifier: nodeUTType.identifier) { data, _ in
            guard let data, let payload = try? JSONDecoder().decode(DragPayload.self, from: data) else { return }
            DispatchQueue.main.async {
                handleDrop(from: payload.path)
            }
            ok = true
        }
        return ok
    }
    
    private func handleDrop(from src: NodePath) {
        guard let tgtNode = vm.node(at: targetPath) else { return }
        if isHeader {
            // 親ヘッダ上 → 子末尾へ
            let parent = targetPath
            let idx = vm.children(of: parent).count
            vm.moveNode(from: src, to: parent, at: idx)
        } else {
            // 行の前/後
            let parent = targetPath.parent
            guard src.depth == targetPath.depth else { return } // 同depthのみ
            let base = targetPath.lastIndex
            let idx = (position == .before) ? base : (base + 1)
            vm.moveNode(from: src, to: parent, at: idx)
        }
    }
}

// MARK: - 葉行（contextMenu + DnD）

struct LeafRow<D>: View where D: Hashable {
    @ObservedObject var vm: PinnedTreeViewModel<D>
    let path: NodePath
    let depth: Int
    let content: AnyView
    let onRename: ((NodePath) -> Void)?
    let onDelete: ((NodePath) -> Void)?
    
    @State private var hoverBefore = false
    @State private var hoverAfter = false
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().frame(height: hoverBefore ? 3 : 1).opacity(hoverBefore ? 1 : 0.15)
            HStack(spacing: 8) {
                Color.clear.frame(width: CGFloat(depth) * 16 + 14)
                content
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .contextMenu {
                Button { onRename?(path) } label: { Label("名前を変更", systemImage: "pencil") }
                Button(role: .destructive) { onDelete?(path) } label: { Label("削除", systemImage: "trash") }
            }
            .onDrag {
                let data = try? JSONEncoder().encode(DragPayload(path: path))
                return NSItemProvider(item: (data as NSData?), typeIdentifier: nodeUTType.identifier)
            }
            Rectangle().frame(height: hoverAfter ? 3 : 1).opacity(hoverAfter ? 1 : 0.15)
        }
        .onDrop(of: [nodeUTType.identifier],
                delegate: NodeDropDelegate(vm: vm, targetPath: path, position: .before, isHeader: false, hover: $hoverBefore))
        .background(
            Rectangle().fill(.clear).onDrop(of: [nodeUTType.identifier],
                                            delegate: NodeDropDelegate(vm: vm, targetPath: path, position: .after, isHeader: false, hover: $hoverAfter))
        )
    }
}

// MARK: - 再帰レンダラ（Section風ヘッダをpin）

struct PinnedTreeRenderer<D>: View where D: Hashable {
    @ObservedObject var vm: PinnedTreeViewModel<D>
    let path: NodePath
    let title: (TreeNode<D>) -> AnyView
    let subtitle: ((TreeNode<D>) -> AnyView)?
    let leafContent: (TreeNode<D>) -> AnyView
    let onCreateChild: ((NodePath) -> Void)?
    let onRename: ((NodePath) -> Void)?
    let onDelete: ((NodePath) -> Void)?
    
    @State private var hoverHeader = false
    
    var body: some View {
        if let node = vm.node(at: path) {
            Section {
                if node.isExpanded, !node.children.isEmpty {
                    ForEach(node.children.indices, id: \.self) { idx in
                        let childPath = NodePath(indices: path.indices + [idx])
                        if let child = vm.node(at: childPath) {
                            if child.children.isEmpty {
                                LeafRow(vm: vm,
                                        path: childPath,
                                        depth: childPath.depth,
                                        content: leafContent(child),
                                        onRename: onRename,
                                        onDelete: onDelete)
                            } else {
                                PinnedTreeRenderer(vm: vm,
                                                   path: childPath,
                                                   title: title,
                                                   subtitle: subtitle,
                                                   leafContent: leafContent,
                                                   onCreateChild: onCreateChild,
                                                   onRename: onRename,
                                                   onDelete: onDelete)
                            }
                        }
                    }
                }
            } header: {
                HeaderRow<D>(
                    depth: path.depth,
                    hasChildren: !node.children.isEmpty,
                    isExpanded: node.isExpanded,
                    title: title(node),
                    subtitle: subtitle.map { $0(node) },
                    onToggle: { vm.toggleExpand(path) }
                )
                .contextMenu {
                    Button { onCreateChild?(path) } label: { Label("子を追加", systemImage: "plus") }
                    Button { onRename?(path) } label: { Label("名前を変更", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) { onDelete?(path) } label: { Label("削除", systemImage: "trash") }
                }
                .onDrag { // 親自体も移動可（同depthの別親へ）
                    let data = try? JSONEncoder().encode(DragPayload(path: path))
                    return NSItemProvider(item: (data as NSData?), typeIdentifier: nodeUTType.identifier)
                }
                .onDrop(of: [nodeUTType.identifier],
                        delegate: NodeDropDelegate(vm: vm, targetPath: path, position: .on, isHeader: true, hover: $hoverHeader))
                .overlay(alignment: .bottom) {
                    Rectangle().frame(height: hoverHeader ? 3 : 0).foregroundStyle(.tint).opacity(hoverHeader ? 0.9 : 0)
                }
            }
        }
    }
}

// MARK: - ルート：List互換UI（iOS14+）
// Listは使わず、ScrollView + LazyVStack(pinnedViews: [.sectionHeaders]) で全階層ピン留め。
// これで .listSectionHeaderBehavior(.pin) 不要＆API非対応のエラーを回避。

struct PinnedTreeView<D>: View where D: Hashable {
    @ObservedObject var vm: PinnedTreeViewModel<D>
    let title: (TreeNode<D>) -> AnyView
    let subtitle: ((TreeNode<D>) -> AnyView)?
    let leafContent: (TreeNode<D>) -> AnyView
    let onCreateChild: ((NodePath) -> Void)?
    let onRename: ((NodePath) -> Void)?
    let onDelete: ((NodePath) -> Void)?
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(vm.roots.indices, id: \.self) { i in
                    PinnedTreeRenderer(vm: vm,
                                       path: NodePath(indices: [i]),
                                       title: title,
                                       subtitle: subtitle,
                                       leafContent: leafContent,
                                       onCreateChild: onCreateChild,
                                       onRename: onRename,
                                       onDelete: onDelete)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

