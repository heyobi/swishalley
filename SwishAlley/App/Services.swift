import SwiftUI
import StoreKit

/// One-time Pro unlock (StoreKit 2): three more arenas, four more balls and two more modes. The whole core game,
/// the face-to-face duel included, is free forever with no ads.
@MainActor
final class Store: ObservableObject {
    static let productID = "com.heyobi.swishalley.pro"

    @Published private(set) var pro = UserDefaults.standard.bool(forKey: "pro")
    @Published private(set) var product: Product?
    @Published var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    init() {
        if ShotsTour.active { pro = true }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish(); await self?.refresh() }
            }
        }
        Task { await load(); await refresh() }
    }

    func load() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        if ShotsTour.active { owned = true }
        set(owned)
    }

    private func set(_ owned: Bool) {
        pro = owned
        UserDefaults.standard.set(owned, forKey: "pro")
    }

    func buy() async {
        if product == nil { await load() }
        guard let product else { message = String(localized: "The App Store is not reachable right now. Try again later."); return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish(); set(true) }
            case .pending: message = String(localized: "The purchase is waiting for approval.")
            default: break
            }
        } catch {
            message = String(localized: "The purchase did not go through. Nothing was charged.")
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = pro ? String(localized: "Swish Alley Pro is unlocked.") : String(localized: "No earlier purchase was found for this Apple Account.")
    }

    var priceText: String? { product?.displayPrice }
}

/// Asks for a rating only right after a new personal best, after at least three rounds, at most once per
/// version and never more often than every four months. Never on a loss, never mid-game.
enum ReviewGate {
    static func roundPlayed() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: "rounds") + 1, forKey: "rounds")
    }

    static func shouldAsk(afterBest: Bool, defaults d: UserDefaults = .standard, now: Date = Date()) -> Bool {
        guard afterBest, !ShotsTour.active else { return false }
        guard d.integer(forKey: "rounds") >= 3 else { return false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        if d.string(forKey: "reviewVersion") == version { return false }
        let last = d.double(forKey: "reviewAskedAt")
        if last > 0, now.timeIntervalSince1970 - last < 120 * 86_400 { return false }
        d.set(version, forKey: "reviewVersion")
        d.set(now.timeIntervalSince1970, forKey: "reviewAskedAt")
        return true
    }
}
