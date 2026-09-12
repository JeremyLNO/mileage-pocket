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

    @State private var step = 0
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
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                Text("onboarding.welcome.subtitle")
                    .font(.system(size: 17))
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
                        Text(CountryCatalog.flag(for: country)).font(.system(size: 26))
                        Text(CountryCatalog.info(for: country, locale: locale)?.name ?? country)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
                    }
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)

                Text(dependencies.ruleAvailabilityMessage(for: country))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
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
                        Text(LocalizedStringKey("vehicle.type.\(type.rawValue)")).tag(type)
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
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var locationStep: some View {
        stepLayout {
            VStack(spacing: 18) {
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.signal)
                stepTitle("onboarding.location.title", subtitle: "onboarding.location.subtitle")
                Text("onboarding.location.detail")
                    .font(.system(size: 14))
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
                    .font(.system(size: 56))
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
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var paywallStep: some View {
        PaywallView()
            .onDisappear { dependencies.completeOnboarding() }
    }

    // MARK: - Layout helpers

    private func stepTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func stepLayout<Content: View, Action: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            ScrollView { content().padding(.horizontal, 24) }
            Spacer(minLength: 12)
            action().padding(.horizontal, 24).padding(.bottom, 24)
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
