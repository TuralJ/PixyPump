import Foundation
import Observation
import StoreKit

// PixyPump Pro: an optional subscription (monthly / yearly) or a one-off lifetime purchase.
// Tracking, plans and calories stay free; Pro adds every cosmetic, a weekly streak freeze,
// and supports the app. Purchases go through StoreKit 2; nothing about them is stored on our side.
//
// Set the three products up in App Store Connect with exactly these IDs (see docs/ARCHITECTURE.md → Pro).
// For testing in the simulator: Product → Scheme → Edit Scheme → Run → Options →
// StoreKit Configuration → PixyPump.storekit.

nonisolated enum ProConfig {
    static let monthly = "com.magsudturalgymapp.pixypump.pro.monthly"
    static let yearly = "com.magsudturalgymapp.pixypump.pro.yearly"
    static let lifetime = "com.magsudturalgymapp.pixypump.pro.lifetime"
    /// In the order the paywall shows them.
    static let productIDs = [monthly, yearly, lifetime]
    /// The plan picked when the paywall opens.
    static let defaultPlan = yearly
    /// Apple's standard licence agreement (App Review requires a link to the terms on the paywall).
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// "Is Pro" remembered between launches, so code that isn't a screen (unlock checks, the streak)
/// can read it straight away. StoreKit checks the real purchases again on every launch.
nonisolated enum ProStatus {
    static let key = "pro.active.v1"
    /// When Pro first switched on (the weekly streak shield only covers days after this).
    static let sinceKey = "pro.since.v1"
    /// Days the shield saved, kept even if Pro ends so a streak never shrinks afterwards.
    static let shieldDaysKey = "pro.shieldDays.v1"

    static var isActive: Bool { UserDefaults.standard.bool(forKey: key) }

    static var since: Date? {
        let t = UserDefaults.standard.double(forKey: sinceKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var shieldDays: Set<Date> {
        get {
            let times = UserDefaults.standard.array(forKey: shieldDaysKey) as? [Double] ?? []
            return Set(times.map { Date(timeIntervalSince1970: $0) })
        }
        set {
            UserDefaults.standard.set(newValue.map(\.timeIntervalSince1970).sorted(), forKey: shieldDaysKey)
        }
    }
}

/// Everything cosmetic unlocked: Pro, or owner mode in Debug builds.
nonisolated enum Unlocks {
    static var everything: Bool { DevMode.unlockAll || ProStatus.isActive }
}

nonisolated enum ProError: LocalizedError {
    case unverified
    var errorDescription: String? {
        "The App Store couldn't confirm this purchase. If you were charged, tap Restore purchases."
    }
}

@MainActor @Observable
final class ProStore {
    static let shared = ProStore()

    /// Monthly, yearly, lifetime (whichever the App Store returned).
    private(set) var products: [Product] = []
    private(set) var isPro = ProStatus.isActive
    /// The plan you're on (nil when not Pro).
    private(set) var activeProductID: String?
    private(set) var isLoading = false
    /// Couldn't reach the App Store (offline, or products not set up yet).
    private(set) var loadFailed = false
    /// Can this person still get the free trial on the yearly plan?
    private(set) var trialEligible = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Purchases made elsewhere (another device, Ask to Buy approved, a refund) arrive here.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
    }

    /// Called once at launch.
    func start() async {
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        guard products.isEmpty else {
            await refreshTrialEligibility()     // can change after a purchase, refund or lapse
            return
        }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProConfig.productIDs)
            products = ProConfig.productIDs.compactMap { id in loaded.first { $0.id == id } }
            loadFailed = products.isEmpty
            await refreshTrialEligibility()
        } catch {
            loadFailed = true
        }
    }

    /// The trial is once per Apple ID per subscription group, so ask the App Store each time the paywall opens.
    private func refreshTrialEligibility() async {
        guard let subscription = product(ProConfig.yearly)?.subscription, subscription.introductoryOffer != nil else {
            trialEligible = false
            return
        }
        trialEligible = await subscription.isEligibleForIntroOffer
    }

    func product(_ id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// Looks at what this Apple ID owns right now and updates `isPro`.
    func refreshEntitlements() async {
        var active: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProConfig.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let expiry = transaction.expirationDate, expiry < .now { continue }
            active = transaction.productID
            if transaction.productID == ProConfig.lifetime { break }
        }
        // Save first, so unlock checks that read `ProStatus` agree when screens react to `isPro`.
        UserDefaults.standard.set(active != nil, forKey: ProStatus.key)
        if active != nil, ProStatus.since == nil {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: ProStatus.sinceKey)
        }
        activeProductID = active
        isPro = active != nil
    }

    enum PurchaseOutcome {
        case purchased, pending, cancelled
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw ProError.unverified }
            await transaction.finish()
            await refreshEntitlements()
            return .purchased
        case .pending:
            return .pending     // Ask to Buy, or the bank needs a confirmation
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// "Restore purchases": asks the App Store for this Apple ID's purchases again.
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }
}
