import Foundation
import StoreKit

@Observable
class StoreManager {
    // Product IDs - configure these in App Store Connect
    static let proMonthly = "isletiq.pro.monthly"
    static let proPlusMonthly = "isletiq.proplus.monthly"
    static let familyMonthly = "isletiq.family.monthly"
    static let proAnnual = "isletiq.pro.annual"

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading = false

    var isPro: Bool {
        purchasedProductIDs.contains(Self.proMonthly) ||
        purchasedProductIDs.contains(Self.proPlusMonthly) ||
        purchasedProductIDs.contains(Self.familyMonthly) ||
        purchasedProductIDs.contains(Self.proAnnual)
    }

    var currentTier: String {
        if purchasedProductIDs.contains(Self.familyMonthly) { return "family" }
        if purchasedProductIDs.contains(Self.proPlusMonthly) { return "pro_plus" }
        if purchasedProductIDs.contains(Self.proMonthly) || purchasedProductIDs.contains(Self.proAnnual) { return "pro" }
        return "trial"
    }

    init() {
        // Listen for transaction updates
        Task { await listenForTransactions() }
        Task { await loadProducts() }
        Task { await updatePurchasedProducts() }
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: [
                Self.proMonthly,
                Self.proPlusMonthly,
                Self.familyMonthly,
                Self.proAnnual,
            ])
            products.sort { $0.price < $1.price }
        } catch {
            print("[store] Failed to load products: \(error)")
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                await syncTierToBackend()
                return true

            case .userCancelled:
                return false

            case .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
            print("[store] Purchase failed: \(error)")
            return false
        }
    }

    // MARK: - Restore

    func restore() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Check Entitlements

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }

        await MainActor.run {
            purchasedProductIDs = purchased
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
                await updatePurchasedProducts()
                await syncTierToBackend()
            }
        }
    }

    // MARK: - Sync tier to backend

    private func syncTierToBackend() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/profile") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tier": currentTier])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
