//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData


struct PackListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]
    private let rowHeight: CGFloat = 44
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var listID = UUID() // Listリフレッシュ用

    @State var editingPack: M1Pack? = nil

    
    var body: some View {
        ZStack {
            NavigationView {
                List {
                    ForEach(packs) { pack in
                        ZStack {
                            PackRowView(pack: pack)
                            
                            HStack(spacing: 0) {
                                Spacer()
                                NavigationLink(destination: GroupListView(pack: pack)) {
                                    Color.clear
                                }
                                .frame(width: 180)
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                                .background(Color.clear).contentShape(Rectangle()) //タップ領域
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .onMove(perform: movePack)
                    .environment(\.editMode, .constant(.active))
                }
                .listStyle(.plain)
                .id(listID)   // listIDが変わるとListが作り直される
                .padding(.top, -8) // headerとPackList間の余白を無くす
                .padding(.horizontal, 0)
                .navigationBarHidden(true)
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button { }
                        label: {
                            Image(systemName: "info.circle")
                        }
                        .padding(.horizontal, 8)
                        
                        Button {
                            withAnimation {
                                modelContext.undoManager?.undo()
                            }
                            listID = UUID()  // ここで List を再描画
                            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                            //updateUndoRedo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!canUndo)
                        .padding(.horizontal, 8)
                        
                        //    Button {
                        //        withAnimation {
                        //            modelContext.undoManager?.redo()
                        //        }
                        //        listID = UUID()  // ここで List を再描画
                        //        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                        //        //updateUndoRedo()
                        //    } label: {
                        //        Image(systemName: "arrow.uturn.forward")
                        //    }
                        //    .disabled(!canRedo)
                        //    .padding(.horizontal, 8)
                        
                        Spacer()
                        Text("モチメモ")
                        Spacer()
                        
                        Button {
                            // Setting
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .padding(.horizontal, 8)
                        
                        Button { addPack() }
                        label: {
                            Image(systemName: "plus.message")
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(height: rowHeight)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial)
                    .onAppear { updateUndoRedo() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            //----------------------------------
            //(ZStack 1) PopupでEditKeyDefView表示
            if let pack = editingPack {
                PopupView(
                    onDismiss: { editingPack = nil }
                ) {
                    EditPackView(pack: pack)
                }
                .zIndex(1) // これが無いとSettingViewの下になる
                
            }
        }
    }

    func editPack(_ pack: M1Pack) {
        editingPack = pack
    }
    
    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        }
    }

    private func addPack() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        let newPack = M1Pack(name: "", order: M1Pack.nextPackOrder(packs))
        modelContext.insert(newPack)
    }

    private func movePack(from source: IndexSet, to destination: Int) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        var items = packs
        items.move(fromOffsets: source, toOffset: destination)
        for (index, pack) in items.enumerated() {
            pack.order = index
        }
    }
}

#Preview {
    PackListView()
}
