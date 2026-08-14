//  AIクレジット購入画面
//  StoreKit購入とサーバー検証を簡潔にまとめる
//

import StoreKit
import SwiftUI

struct ChappyCreditPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var creditStore: CreditStore

    @State private var products: [Product] = []
    @State private var processingProductId: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(String(format: String(localized: "chappy.credits.balance", defaultValue: "残高 %lld クレジット"), Int64(creditStore.credits)))
                    .font(.headline)

                ForEach(AZUKI_CREDIT_PURCHASE_OPTIONS, id: \.productIdJapan) { option in
                    Button {
                        purchase(option)
                    } label: {
                        HStack {
                            if processingProductId == option.productId(for: locale) {
                                ProgressView()
                            }
                            Text(option.localizedButtonTitle(for: locale))
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(processingProductId != nil)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle(String(localized: "chappy.buy.credits", defaultValue: "AIクレジットを購入"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
            .task {
                // 表示時に商品情報と認証用トークンを準備する
                await loadProducts()
                await refreshBalance()
            }
        }
    }

    private func loadProducts() async {
        let identifiers = Set(AZUKI_CREDIT_PURCHASE_OPTIONS.map { $0.productId(for: locale) })
        do {
            products = try await Product.products(for: identifiers)
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshBalance() async {
        do {
            let status = try await AzukiApi.shared.fetchCreditStatus(userId: creditStore.regenerateUserIdIfNeeded())
            creditStore.overwriteFromServer(credits: status.balance)
        } catch {
            // 購入前の残高照会失敗は購入ボタンを妨げず、検証時のエラーに任せる
        }
    }

    private func purchase(_ option: AzukiCreditPurchaseOption) {
        let productId = option.productId(for: locale)
        processingProductId = productId
        message = nil
        Task {
            defer { processingProductId = nil }
            do {
                let product: Product?
                if let cached = products.first(where: { $0.id == productId }) {
                    product = cached
                } else {
                    // 商品キャッシュが空なら対象商品だけを再取得する
                    product = try await Product.products(for: [productId]).first
                }
                guard let product else {
                    throw AzukiAPIError.unknownProduct
                }
                let outcome = try await product.purchase()
                guard case .success(let verification) = outcome else { return }
                guard case .verified(let transaction) = verification else {
                    throw AzukiAPIError.purchaseMismatch
                }

                let result = try await AzukiApi.shared.verifyPurchase(
                    userId: creditStore.regenerateUserIdIfNeeded(),
                    productId: productId,
                    transactionId: String(transaction.id),
                    receipt: transaction.jsonRepresentation.base64EncodedString(),
                    storekitJws: verification.jwsRepresentation,
                    grantCredits: option.tickets
                )
                creditStore.overwriteFromServer(credits: result.balance)
                await transaction.finish()
                message = String(format: String(localized: "chappy.credits.added", defaultValue: "%lldクレジットを追加しました"), Int64(option.tickets))
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
