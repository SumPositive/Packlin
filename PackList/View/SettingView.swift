//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices
import SwiftData
import UniformTypeIdentifiers
import Foundation

/// 設定画面：Popupで表示する
struct SettingView: View {
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape")
                Text("setting.title")
                Spacer()
            }
            .padding(8)
            
            // アプリの紹介・取扱説明
            InformationView()
                .padding(.vertical, 8)

            // カスタム設定
            CustomSetView()
                .padding(.vertical, 8)

            /// 寄付
            DonationView()
                .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 300, height: 500)
        .onAppear {
        }
        .onDisappear() {
        }
    }
    
    /// カスタムSafariシート
    struct SafariView: UIViewControllerRepresentable {
        let url: URL
        func makeUIViewController(context: Context) -> SFSafariViewController {
            return SFSafariViewController(url: url)
        }
        func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    }

    /// アプリの紹介・取扱説明
    struct InformationView: View {
        @State private var showSafari = false
        
        var body: some View {
            Button(action: {
                //withAnimation {
                    // SafariでURLを表示する
                    showSafari = true
                //}
            }) {
                Image(systemName: "info.circle")
                Text("setting.info")
                Spacer()
            }
            .padding(8)
            .sheet(isPresented: $showSafari) {
                let urlString = String(localized: "info.url")
                if let url = URL(string: urlString) {
                    SafariView(url: url)
                } else {
                    Text("setting.infoUnavailable")
                }
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(10)
        }
    }

    /// カスタム設定
    struct CustomSetView: View {
        @Environment(\.modelContext) private var modelContext
        @State private var isPresentingImporter = false
        @State private var importErrorMessage: String?

        var body: some View {
            VStack {
                Button(action: {
                    isPresentingImporter = true
                }) {
                    Image(systemName: "arrow.down.message")
                    Text("action.json.download")
                    Spacer()
                }
                .padding(8)
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(10)
            .fileImporter(
                isPresented: $isPresentingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try importPack(from: url)
                    } catch {
                        debugPrint("Failed to import pack: \(error)")
                        importErrorMessage = String(localized: "setting.import.error.message")
                    }
                case .failure(let error):
                    debugPrint("Failed to import pack: \(error)")
                    importErrorMessage = String(localized: "setting.import.error.message")
                }
            }
            .alert(
                "setting.import.error.title",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }

        /// URLよりJSONファイルをPackExportDTO形式で読み取る
        private func importPack(from url: URL) throws {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let dto = try decoder.decode(PackJsonDTO.self, from: data)

            // チェック
            if dto.copyright != PACK_JSON_DTO_COPYRIGHT {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Copyright mismatch."])
            }
            if dto.version != PACK_JSON_DTO_VERSION {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Version mismatch."])
            }

            try createPack(from: dto)
        }

        /// DTOよりPackを追加する
        private func createPack(from dto: PackJsonDTO) throws {
            let descriptor = FetchDescriptor<M1Pack>()
            let packs = (try? modelContext.fetch(descriptor)) ?? []
            let newOrder = M1Pack.nextPackOrder(packs)

            let undoManager = modelContext.undoManager
            undoManager?.beginUndoGrouping()
            defer {
                if let undoManager, undoManager.groupingLevel > 0 {
                    undoManager.endUndoGrouping()
                    NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                }
            }
            // PackJsonDTO をDBへインポートする
            PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
        }
    }
    
    /// 寄付
    struct DonationView: View {
        @State private var showAd = false
        @State private var showAdMovie = false
        @State private var showDonate = false

        var body: some View {
            VStack {
                HStack {
                    Image(systemName: "heart")
                    Text("ad.empowering.developers")
                    Spacer()
                }
                .padding(8)
                VStack {
                    HStack {
                        // 広告を見て寄付する（ボタン）
                        Button(action: {
                            withAnimation {
                                // SafariでURLを表示する
                                showAd = true
                            }
                        }) {
                            Text("ad.donate.banner")
                        }
                        .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                        .sheet(isPresented: $showAd) {
                            AdMobBannerContainerView()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    
                    HStack {
                        // 動画広告を見て寄付する（ボタン）
                        Button(action: {
                            withAnimation {
                                // SafariでURLを表示する
                                showAdMovie = true
                            }
                        }) {
                            Text("ad.donate.video")
                        }
                        .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                        .sheet(isPresented: $showAdMovie) {
                            AdMobVideoContainerView()
                        }
                        HStack(spacing: 0) {
                            Image(systemName: "exclamationmark.triangle")
                                .imageScale(.small)
                            Text("ad.video.sound").font(.caption)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .padding(.leading, 26)
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(10)
        }
    }

}

#Preview {
    SettingView()
}
