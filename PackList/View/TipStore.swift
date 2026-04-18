// TipStore.swift
// StoreKit2 ベースのチップ購入（開発者応援）

import StoreKit
import Observation

@Observable
@MainActor
final class TipStore {

    static let shared = TipStore()

    private let productIds: [String] = [
        "Packlin_Tips_1",
        "Packlin_Tips_5",
    ]

    var products: [Product] = []
    var isPurchasing = false
    var isLoadingProducts = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let loaded = (try? await Product.products(for: productIds)) ?? []
        products = loaded.sorted { $0.price < $1.price }
    }

    /// 購入実行。成功時 true を返す
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                return true
            }
        } catch {}
        return false
    }
}
