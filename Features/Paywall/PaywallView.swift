import StoreKit
import SwiftUI

/// The paywall.
///
/// Every price on this screen comes from StoreKit's `displayPrice`, and the annual saving is
/// computed from the two live prices — a hard-coded "€2.99" is wrong in every storefront but
/// one, and App Review checks.
///
/// It can always be dismissed. A paywall with no exit is a common rejection, and the spec is
/// explicit that a person's own data must stay reachable without paying.
struct PaywallView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedProductID = ProductIDs.annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    private var service: SubscriptionService { dependencies.subscriptions }

    private var selectedProduct: Product? {
        service.products.first { $0.id == selectedProductID }
    }

    private var selectedPlan: PaywallPlan? {
        service.plans.first { $0.id == selectedProductID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    header
                    features
                    plans
                    callToAction
                    legal
                }
                .padding(20)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("common.close"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("paywall.restore") { Task { await restore() } }
                        .font(.system(size: 14))
                }
            }
        }
        .task {
            if service.products.isEmpty { await service.load() }
        }
        .alert("paywall.error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.signal)
            Text("paywall.headline")
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 8)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.featureKeys(), id: \.self) { key in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.business)
                    Text(LocalizedStringKey(key))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// iCloud backup is listed only when the build can actually do it. Promising a backup
    /// that does not happen is the one claim on this screen that could cost someone data.
    static func featureKeys() -> [String] {
        var keys = [
            "paywall.feature.tracking",
            "paywall.feature.calculations",
            "paywall.feature.pdf",
            "paywall.feature.csv",
            "paywall.feature.vehicles",
        ]
        if CloudKitAvailability.isEntitled {
            keys.append("paywall.feature.icloud")
        }
        return keys
    }

    @ViewBuilder
    private var plans: some View {
        if service.plans.isEmpty {
            // A paywall that spins forever is a dead end. When the store cannot be reached,
            // say so and offer a retry — and never leave the user with no way off the screen.
            VStack(spacing: 10) {
                if service.isLoading {
                    ProgressView()
                } else {
                    Text("paywall.unavailable")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    if let error = service.lastError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("paywallError")
                    }
                    Button("paywall.retry") { Task { await service.load() } }
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .frame(height: 120)
        } else {
            HStack(spacing: 12) {
                ForEach(service.plans) { plan in
                    planCard(plan)
                }
            }
        }
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let isSelected = plan.id == selectedProductID
        return Button {
            selectedProductID = plan.id
        } label: {
            VStack(spacing: 6) {
                if plan.isAnnual, let saving = service.annualSavingsPercent {
                    Text(L.format("paywall.save", saving))
                        .eyebrowStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.business, in: Capsule())
                } else {
                    Color.clear.frame(height: 19)
                }

                Text(plan.isAnnual ? "paywall.plan.annual" : "paywall.plan.monthly")
                    .eyebrowStyle(Theme.textSecondary)

                Text(plan.displayPrice)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)

                Text(plan.isAnnual ? "paywall.per.year" : "paywall.per.month")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Theme.signal.opacity(0.12) : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Theme.signal : Theme.separator, lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var callToAction: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: hasIntroductoryOffer ? "paywall.cta.trial" : "paywall.cta.subscribe",
                isEnabled: selectedPlan != nil && !isPurchasing
            ) {
                Task { await purchase() }
            }

            if let plan = selectedPlan {
                Text(footerText(for: plan))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var hasIntroductoryOffer: Bool { selectedPlan?.hasIntroductoryOffer ?? false }

    /// "3 days free, then €29.99. Cancel anytime." — the price is the store's own string, so
    /// the sentence is correct in every currency.
    private func footerText(for plan: PaywallPlan) -> String {
        if plan.hasIntroductoryOffer {
            return String(format: String(localized: "paywall.footer.trial"), plan.displayPrice)
        }
        return String(format: String(localized: "paywall.footer.plain"), plan.displayPrice)
    }

    private var legal: some View {
        HStack(spacing: 16) {
            Button("paywall.terms") { open(AppLinks.terms) }
            Button("paywall.privacy") { open(AppLinks.privacy) }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }

    private func purchase() async {
        guard let selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if try await service.purchase(selectedProduct) {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        do {
            try await service.restore()
            if service.entitlement.isActive { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// URLs come from the build configuration, not from string literals scattered in views —
/// see `Config/Base.xcconfig` and the `SLASH` note there.
enum AppLinks {
    static var privacy: URL? { url(for: "PrivacyPolicyURL") }
    static var terms: URL? { url(for: "TermsURL") }
    static var support: URL? { url(for: "SupportURL") }
    static var rulePackEndpoint: URL? { url(for: "RulePackURL") }

    private static func url(for key: String) -> URL? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        return URL(string: string)
    }
}
