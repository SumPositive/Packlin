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
    private var isNamePlaceholder: Bool { pack.name.isEmpty }
    private var weightUnit: String { String(localized: "unit.gram") }
    
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
                        pack.name.placeholderText("placeholder.pack.new")
                            .lineLimit(3)
                            .font(FONT_NAME)
                            .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                        
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
                                Text(verbatim: "\(pack.stockWeight)\(weightUnit)／\(pack.needWeight)\(weightUnit)")
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
                    // Row本体に置くとRowサイズが固定化されてしまうため
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                rowFrame = geo.frame(in: .global)
                            }
                            .onChange(of: geo.frame(in: .global)) { newFrame, oldFrame in
                                rowFrame = newFrame
                            }
                    }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let rf = rowFrame else { return }
                            let location = value.location
                            let po = CGPoint(x: rf.width / 2.0,
                                             y: rf.minY + location.y)
                            onEdit(pack, po)
                        }
                )
            }
    }

}

