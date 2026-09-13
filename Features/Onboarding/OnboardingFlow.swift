import CoreLocation
import SwiftUI
import SwiftData

/// Six screens, none of them optional-feeling and none of them long.
///
/// Permissions are asked for on the screen that explains them and nowhere earlier: a
/// location prompt that appears before the user knows what the app does is the prompt they
/// deny.
struct OnboardingFlow: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @State private var step = DemoMode.onboardingStep ?? 0
    @State private var country = CountryCatalog.detectedCountryCode()
    @State private var vehicleName = ""
    @State private var vehicleType = VehicleType.car
    @State private var registration = ""
    @State private var fiscalPower: Int?
    @State private var engineCapacity: Int?
    @State private var showsCountryPicker = false

    private let lastStep = 5

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            TabView(selection: $step) {
                welcome.tag(0)
                countryStep.tag(1)
                vehicleStep.tag(2)
                locationStep.tag(3)
                notificationsStep.tag(4)
                paywallStep.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy(duration: 0.25), value: step)
        }
        .background(Theme.background)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separator)
                Capsule()
                    .fill(Theme.signal)
                    .frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(lastStep + 1))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Steps

    private var welcome: some View {
        stepLayout {
            VStack(spacing: 20) {
                Image("AppIconArtwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Text("onboarding.welcome.headline")
                    .scaledFont(32, relativeTo: .largeTitle, weight: .bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                Text("onboarding.welcome.subtitle")
                    .scaledFont(17, relativeTo: .body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
        } action: {
            PrimaryButton(title: "common.continue") { advance() }
        }
    }

    private var countryStep: some View {
        stepLayout {
            VStack(spacing: 18) {
                stepTitle("onboarding.country.title", subtitle: "onboarding.country.subtitle")
                Button {
                    showsCountryPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Text(CountryCatalog.flag(for: country)).scaledFont(26, relativeTo: .title2)
                        Text(CountryCatalog.info(for: country, locale: locale)?.name ?? country)
                            .scaledFont(18, relativeTo: .title3, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
                    }
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)

                Text(dependencies.ruleAvailabilityMessage(for: country))
                    .scaledFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } action: {
            PrimaryButton(title: "common.continue") {
                dependencies.settingsStore.applyCountry(country)
                advance()
            }
        }
        .sheet(isPresented: $showsCountryPicker) {
            CountryPickerSheet(selection: $country)
        }
    }

    private var vehicleStep: some View {
        stepLayout {
            VStack(spacing: 14) {
                stepTitle("onboarding.vehicle.title", subtitle: "onboarding.vehicle.subtitle")

                TextField("vehicle.name", text: $vehicleName)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Picker("vehicle.type", selection: $vehicleType) {
                    ForEach(VehicleType.allCases, id: \.self) { type in
                        Text(L.string("vehicle.type.\(type.rawValue)")).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                TextField("vehicle.registration", text: $registration)
                    .textInputAutocapitalization(.characters)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Only asked where the country's own scale actually bands by it.
                switch dependencies.requiredPowerUnit(countryCode: country) {
                case .fiscalHorsepower:
                    TextField("vehicle.fiscal.horsepower", value: $fiscalPower, format: .number)
                        .keyboardType(.numberPad)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .engineCapacity:
                    TextField("vehicle.engine.capacity", value: $engineCapacity, format: .number)
                        .keyboardType(.numberPad)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                case nil:
                    EmptyView()
                }
            }
        } action: {
            VStack(spacing: 10) {
                PrimaryButton(title: "common.continue") {
                    if !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty {
                        dependencies.createOnboardingVehicle(
                            name: vehicleName,
                            type: vehicleType,
                            registration: registration,
                            fiscalHorsepower: fiscalPower,
                            engineCapacity: engineCapacity
                        )
                    }
                    advance()
                }
                Button("onboarding.skip") { advance() }
                    .scaledFont(15, relativeTo: .subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var locationStep: some View {
        stepLayout {
            VStack(spacing: 18) {
                Image(systemName: "location.fill.viewfinder")
                    .scaledFont(56, relativeTo: .largeTitle)
                    .foregroundStyle(Theme.signal)
                stepTitle("onboarding.location.title", subtitle: "onboarding.location.subtitle")
                Text("onboarding.location.detail")
                    .scaledFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        } action: {
            PrimaryButton(title: "onboarding.location.allow") {
                dependencies.requestLocationPermission()
                advance()
            }
        }
    }

    private var notificationsStep: some View {
        stepLayout {
            VStack(spacing: 18) {
                Image(systemName: "bell.badge.fill")
                    .scaledFont(56, relativeTo: .largeTitle)
                    .foregroundStyle(Theme.signal)
                stepTitle("onboarding.notifications.title", subtitle: "onboarding.notifications.subtitle")
            }
        } action: {
            VStack(spacing: 10) {
                PrimaryButton(title: "onboarding.notifications.allow") {
                    Task {
                        await dependencies.requestNotificationPermission()
                        advance()
                    }
                }
                Button("onboarding.skip") { advance() }
                    .scaledFont(15, relativeTo: .subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var paywallStep: some View {
        // Closing the paywall here means "finish onboarding without subscribing", not
        // "dismiss a sheet": there is no sheet to dismiss, so the action is passed in.
        PaywallView(onClose: { dependencies.completeOnboarding() })
    }

    // MARK: - Layout helpers

    private func stepTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .scaledFont(27, relativeTo: .title2, weight: .bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .scaledFont(16, relativeTo: .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                // Without this the subtitle loses its layout negotiation against the controls
                // below it and is truncated to one line — "…and the mile…" on the country step.
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Content is centred in the space left above the action, but still scrolls when it does
    /// not fit — which it will not at the larger Dynamic Type sizes. A plain `ScrollView`
    /// pins short content to the top and leaves a void above the button.
    private func stepLayout<Content: View, Action: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        // The builders are evaluated once, here: `GeometryReader`'s closure escapes, and a
        // @ViewBuilder parameter does not.
        let body = content()
        let footer = action()
        return VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    body
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
            }
            footer.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
        }
    }

    private func advance() {
        if step >= lastStep {
            dependencies.completeOnboarding()
        } else {
            step += 1
        }
    }
}
