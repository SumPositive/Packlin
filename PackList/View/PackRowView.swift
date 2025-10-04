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
    @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = false
    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { pack.name.isEmpty }
    private var weightUnit: String { String(localized: "unit.gram") }

    private var weightLabelText: String? {
        if showNeedWeight {
            guard pack.stockWeight > 0 || pack.needWeight > 0 else { return nil }
            return "\(pack.stockWeight.decimalGrouped)\(weightUnit)／\(pack.needWeight.decimalGrouped)\(weightUnit)"
        } else {
            guard pack.stockWeight > 0 else { return nil }
            return "\(pack.stockWeight.decimalGrouped)\(weightUnit)"
        }
    }
    
    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // 編集
                    Button {
                        guard let rf = rowFrame else { return }
                        let po = CGPoint(x: rf.width / 2.0,
                                         y: rf.minY)
                        onEdit(pack, po)
                    } label: {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)

                            if allItemsChecked {
                                Image(systemName: "checkmark")
                                    .imageScale(.small)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.leading, 0)
                        .padding(.trailing, 8)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    // 名称
                    pack.name.placeholderText("placeholder.pack.new")
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                    Spacer()
                }

                HStack(spacing: 0) {
                    Rectangle()
                        .frame(width: 24, height: 1)
                        .foregroundStyle(.clear)
                    
                    if let weightLabelText = weightLabelText {
                        Text(verbatim: weightLabelText)
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(COLOR_ROW_GROUP.opacity(0.85))
                            )
                    }else{
                        Rectangle()
                            .frame(width: 24, height: 1)
                            .foregroundStyle(.clear)
                    }
                    // メモ
                    if !pack.memo.isEmpty {
                        Text(pack.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.horizontal, 8)
                    }
                    Spacer()
                }
                // DEBUG Line
                if DEBUG_SHOW_ORDER_ID {
                    Text("pack (\(pack.order)) [\(pack.id)]")
                }
            }
            .frame(minHeight: rowHeight)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                // Row本体に置くとRowサイズが固定化されてしまうため
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            rowFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.frame(in: .global)) { oldFrame, newFrame in
                            rowFrame = newFrame
                        }
                }
            )
            .overlay(alignment: .bottom) {
                // 独自の下線
                COLOR_LIST_SEPARATOR
                    .frame(height: LIST_SEPARATOR_THICKNESS)
                    .ignoresSafeArea(edges: .horizontal)
                    .padding(.horizontal, 50)
            }
        }
    }

}

