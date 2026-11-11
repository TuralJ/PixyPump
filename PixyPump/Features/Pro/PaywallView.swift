import SwiftUI
import StoreKit

// The PixyPump Pro paywall (design: Figma "gym-app" → 02 Paywall).
// Honest by default: the price after the trial and how to cancel are always on screen,
// prices come from the App Store (never typed in here), and tracking stays free.

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = ProStore.shared

    @State private var selectedID = ProConfig.defaultPlan
    @State private var purchasing = false
    @State private var restoring = false
    @State private var message: String?
    @State private var showPrivacy = false
    @State private var showManage = false

    private var selected: Product? { store.product(selectedID) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background
            if store.isPro {
                proView
            } else {
                ScrollView {
                    VStack(spacing: DS.Space.xl) {
                        hero
                        features
                        plans
                        purchaseArea
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.xxl + DS.Space.l)
                    .padding(.bottom, DS.Space.xl)
                }
                .scrollIndicators(.hidden)
            }
            closeButton
        }
        .task { await store.loadProducts() }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                LegalView(document: .privacy)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showPrivacy = false } }
                    }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .alert("\(AppInfo.name) Pro", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { Haptics.success() }
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            AppBackground()
            Ellipse()
                .fill(Color.ppMuted.opacity(0.4))
                .frame(width: 520, height: 300)
                .blur(radius: 90)
                .offset(y: -330)
            Circle()
                .fill(Color.brand.opacity(0.3))
                .frame(width: 240, height: 240)
                .blur(radius: 80)
                .offset(y: -250)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            Image.pixel(.close, size: 18)
                .foregroundStyle(Color.ppText.opacity(0.8))
                .frame(width: DS.Size.minTap, height: DS.Size.minTap)
                .background(Color.ppCard, in: Circle())
        }
        .buttonStyle(.squish)
        .padding(.trailing, DS.Space.xl)
        .padding(.top, DS.Space.s)
        .accessibilityLabel("Close")
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: DS.Space.s) {
            PixelHammer(cell: 3.5)
                .padding(.bottom, DS.Space.s)
            Text("\(AppInfo.name.uppercased()) PRO")
                .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                .tracking(1)
                .foregroundStyle(Color.ppOnAccent)
                .padding(.horizontal, DS.Space.m - DS.Space.xxs)
                .padding(.vertical, DS.Space.xs)
                .background(Color.ppText, in: Capsule())
            Text("Level up\nyour gym.")
                .font(.pixel(DS.TextSize.largeTitle, relativeTo: .largeTitle))
                .foregroundStyle(Color.ppText)
                .multilineTextAlignment(.center)
            Text("Tracking stays free forever. Pro adds the extras.")
                .font(.subheadline)
                .foregroundStyle(Color.ppText.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Features

    private var features: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            featureRow(.dumbbell, tint: .ppProtein, title: "Every look, unlocked",
                       detail: "All theme packs, app icons, buddy outfits and rest timer skins, right away.")
            featureRow(.fire, tint: .ppFlame, title: "Streak shield",
                       detail: "A free streak freeze every week, so a sick day never breaks your streak.")
            featureRow(.heart, tint: .ppHeart, title: "Keep it indie",
                       detail: "No ads, no selling your data. Pro is how two developers keep it that way.")
        }
        .padding(DS.Space.l + DS.Space.xxs)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    private func featureRow(_ icon: PixelGlyph, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image.pixel(icon, size: 20)
                .foregroundStyle(tint)
                .frame(width: DS.Size.minTap - DS.Space.s, height: DS.Size.minTap - DS.Space.s)
                .background(Color.ppLine.opacity(DS.Opacity.border), in: RoundedRectangle(cornerRadius: DS.Radius.s))
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ppText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.ppText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Plans

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            VStack(spacing: DS.Space.s) {
                if store.isLoading {
                    ProgressView().tint(Color.ppText)
                    Text("Loading prices…").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Couldn't load prices from the App Store.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await store.loadProducts() } }
                        .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                        .foregroundStyle(Color.brand)
                        .frame(minHeight: DS.Size.minTap)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104)
        } else {
            HStack(alignment: .top, spacing: DS.Space.s) {
                ForEach(store.products, id: \.id) { product in
                    planTile(product)
                }
            }
        }
    }

    private func planTile(_ product: Product) -> some View {
        let isSelected = product.id == selectedID
        return Button {
            Haptics.select()
            withAnimation(DS.Motion.spring) { selectedID = product.id }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(planName(product))
                    .font(.footnote)
                    .foregroundStyle(Color.ppText.opacity(0.7))
                Text(product.displayPrice)
                    .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(planDetail(product))
                    .font(.caption)
                    .foregroundStyle(Color.ppText.opacity(0.6))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let saving = savingText(product) {
                    Text(saving)
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                        .foregroundStyle(Color.ppOnAccent)
                        .padding(.horizontal, DS.Space.s - DS.Space.xxs)
                        .padding(.vertical, DS.Space.xxs + 1)
                        .background(Color.ppProtein, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(DS.Space.m)
            .background(Color.ppLine.opacity(isSelected ? DS.Opacity.fill : 0.04),
                        in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .strokeBorder(isSelected ? Color.ppText : Color.ppLine.opacity(DS.Opacity.fill),
                                  lineWidth: isSelected ? 2 : DS.Size.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        }
        .buttonStyle(.squish)
        .accessibilityLabel("\(planName(product)), \(product.displayPrice), \(planDetail(product))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func planName(_ product: Product) -> String {
        switch product.id {
        case ProConfig.monthly: return "Monthly"
        case ProConfig.yearly: return "Yearly"
        default: return "Lifetime"
        }
    }

    private func planDetail(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "pay once" }
        if period.unit == .year, let perMonth = monthlyPrice(product) {
            return "\(perMonth) / month"
        }
        return "per " + periodName(period)
    }

    /// "SAVE 50%" on the yearly plan, worked out from the real prices.
    private func savingText(_ product: Product) -> String? {
        guard product.id == ProConfig.yearly, let monthly = store.product(ProConfig.monthly) else { return nil }
        let fullYear = monthly.price * 12
        guard fullYear > 0, product.price < fullYear else { return nil }
        let percent = NSDecimalNumber(decimal: (fullYear - product.price) / fullYear * 100).intValue
        return percent >= 10 ? "SAVE \(percent)%" : nil
    }

    private func monthlyPrice(_ product: Product) -> String? {
        (product.price / 12).formatted(product.priceFormatStyle)
    }

    private func periodName(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return period.value == 1 ? "day" : "\(period.value) days"
        case .week: return period.value == 1 ? "week" : "\(period.value) weeks"
        case .month: return period.value == 1 ? "month" : "\(period.value) months"
        case .year: return period.value == 1 ? "year" : "\(period.value) years"
        @unknown default: return "period"
        }
    }

    // MARK: Buying

    /// Days of free trial on the selected plan, if this person can still get it.
    private var trialDays: Int? {
        guard store.trialEligible, let offer = selected?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        case .month: return offer.period.value * 30
        case .year: return offer.period.value * 365
        @unknown default: return nil
        }
    }

    private var buttonTitle: String {
        guard let selected else { return "Continue" }
        if let trialDays { return "Start \(trialDays)-day free trial" }
        return selected.subscription == nil ? "Buy lifetime" : "Subscribe"
    }

    /// The terms right under the button, always with the real price.
    private var termsText: String {
        guard let selected else { return "" }
        guard let period = selected.subscription?.subscriptionPeriod else {
            return "One payment of \(selected.displayPrice). Yours to keep, no subscription."
        }
        let every = periodName(period)
        let cancel = "Cancel anytime in Settings → Apple ID → Subscriptions."
        if let trialDays {
            return "Free for \(trialDays) days, then \(selected.displayPrice) per \(every), renews automatically "
                + "until you cancel. Cancel at least 24 hours before the trial ends to avoid being charged. \(cancel)"
        }
        return "\(selected.displayPrice) per \(every), renews automatically until you cancel. \(cancel)"
    }

    private var purchaseArea: some View {
        VStack(spacing: DS.Space.m) {
            Button(action: buy) {
                if purchasing {
                    ProgressView().tint(Color.ppOnAccent)
                } else {
                    Text(buttonTitle)
                }
            }
            .buttonStyle(.primary)
            .disabled(selected == nil || purchasing || restoring)

            Text(termsText)
                .font(.caption)
                .foregroundStyle(Color.ppText.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Side by side, or stacked when large text doesn't fit on one line.
            ViewThatFits {
                HStack(spacing: DS.Space.l) { legalLinks }
                VStack(spacing: DS.Space.xs) { legalLinks }
            }
            .font(.caption)
            .foregroundStyle(Color.ppText.opacity(0.7))
            .frame(minHeight: DS.Size.minTap)
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        Link("Terms of Use", destination: ProConfig.termsURL)
        Button("Privacy Policy") { showPrivacy = true }
        Button(restoring ? "Restoring…" : "Restore purchases", action: restore)
            .disabled(restoring || purchasing)
    }

    private func buy() {
        guard let selected else { return }
        Haptics.press()
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                switch try await store.purchase(selected) {
                case .purchased: break   // the "You're Pro" view takes over
                case .pending: message = "Your purchase is waiting for approval. Pro switches on as soon as it's approved."
                case .cancelled: break
                }
            } catch StoreKitError.userCancelled {
                // Closed the App Store sheet: nothing to say.
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        Haptics.tap()
        restoring = true
        Task {
            defer { restoring = false }
            do {
                try await store.restore()
                if !store.isPro { message = "No Pro purchase found for this Apple ID." }
            } catch StoreKitError.userCancelled {
                // Closed the Apple ID sign-in: nothing to say.
            } catch {
                message = "Couldn't reach the App Store. Check your connection and try again."
            }
        }
    }

    // MARK: Already Pro

    private var proView: some View {
        VStack(spacing: DS.Space.l) {
            Spacer()
            PixelHammer(cell: 4)
                .stamp(store.isPro)
            Text("You're Pro")
                .font(.pixel(DS.TextSize.largeTitle, relativeTo: .largeTitle))
                .foregroundStyle(Color.ppText)
            Text("Every look is unlocked and your weekly streak freeze is on. Thanks for supporting \(AppInfo.name)!")
                .font(.subheadline)
                .foregroundStyle(Color.ppText.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
            if store.activeProductID != ProConfig.lifetime {
                Button("Manage subscription") { showManage = true }
                    .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                    .foregroundStyle(Color.ppText.opacity(0.7))
                    .frame(minHeight: DS.Size.minTap)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
        }
        .padding(DS.Space.xl)
    }
}

/// Settings → PixyPump Pro.
struct ProSection: View {
    private let store = ProStore.shared
    @State private var showingPaywall = false

    var body: some View {
        Section {
            Button {
                Haptics.tap()
                showingPaywall = true
            } label: {
                HStack(spacing: DS.Space.m) {
                    PixelHammer(cell: 1.5)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(store.isPro ? "\(AppInfo.name) Pro" : "Get \(AppInfo.name) Pro")
                            .foregroundStyle(Color.ppText)
                        Text(store.isPro ? "Active · every look unlocked" : "Every look and a weekly streak freeze.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image.pixel(.chevronRight, size: 16)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: DS.Size.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }
}
