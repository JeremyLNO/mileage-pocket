import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    @State private var showsCountryPicker = false
    @State private var showsDeleteConfirmation = false
    @State private var showsPaywall = false
    @State private var exportFile: ExportedFile?
    @State private var exportFailed = false

    private var settings: UserSettings { dependencies.settingsStore.settings }
    private var localization: LocalizationService { dependencies.localization }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                drivingSection
                regionSection
                calculationSection
                notificationsSection
                dataSection
                subscriptionSection
                aboutSection
            }
            .navigationTitle("tab.settings")
            .sheet(isPresented: $showsCountryPicker) {
                CountryPickerSheet(selection: Binding(
                    get: { settings.countryCode },
                    set: { dependencies.settingsStore.applyCountry($0) }
                ))
            }
            .sheet(isPresented: $showsPaywall) { PaywallView() }
            .sheet(item: $exportFile) { file in ShareSheet(url: file.url) }
            .alert("export.failed.title", isPresented: $exportFailed) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("export.failed.message")
            }
            .confirmationDialog("settings.delete.all", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("settings.delete.all.confirm", role: .destructive) { dependencies.deleteAllData() }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.delete.all.message")
            }
        }
    }

    private var accountSection: some View {
        // Labelled rather than placeholder-only: a placeholder disappears the moment a value
        // is typed, and "Jane Doe" on its own does not say which field it is.
        Section("settings.account") {
            LabeledContent("settings.name") {
                TextField("settings.name", text: Binding(
                    get: { settings.userName ?? "" },
                    set: { settings.userName = $0.isEmpty ? nil : $0; dependencies.settingsStore.save() }
                ))
                .multilineTextAlignment(.trailing)
            }
            LabeledContent("settings.company") {
                TextField("settings.company", text: Binding(
                    get: { settings.companyName ?? "" },
                    set: { settings.companyName = $0.isEmpty ? nil : $0; dependencies.settingsStore.save() }
                ))
                .multilineTextAlignment(.trailing)
            }
            LabeledContent("settings.email") {
                TextField("settings.email", text: Binding(
                    get: { settings.email ?? "" },
                    set: { settings.email = $0.isEmpty ? nil : $0; dependencies.settingsStore.save() }
                ))
                .multilineTextAlignment(.trailing)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            }
        }
    }

    private var drivingSection: some View {
        Section("settings.driving") {
            NavigationLink {
                VehiclesView()
            } label: {
                LabeledContent("settings.vehicles", value: dependencies.defaultVehicleName() ?? L.string("home.no.vehicle"))
            }

            NavigationLink {
                ClientsProjectsView()
            } label: {
                Text("settings.clients")
            }

            Picker("settings.default.type", selection: Binding(
                get: { settings.defaultTripType },
                set: { settings.defaultTripType = $0; dependencies.settingsStore.save() }
            )) {
                Text("trip.type.business").tag(TripType.business)
                Text("trip.type.personal").tag(TripType.personal)
            }

            Picker("settings.units", selection: Binding(
                get: { settings.distanceUnit },
                set: { settings.distanceUnit = $0; dependencies.settingsStore.save() }
            )) {
                Text("settings.units.km").tag(DistanceUnit.kilometers)
                Text("settings.units.mi").tag(DistanceUnit.miles)
            }
        }
    }

    private var regionSection: some View {
        Section("settings.region") {
            Button {
                showsCountryPicker = true
            } label: {
                LabeledContent("settings.country") {
                    Text(CountryCatalog.info(for: settings.countryCode, locale: locale)?.name ?? settings.countryCode)
                }
            }
            .foregroundStyle(Theme.textPrimary)

            Picker("settings.language", selection: Binding(
                get: { localization.currentLanguage },
                set: { localization.setLanguage($0); dependencies.settingsStore.save() }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }

            LabeledContent("settings.currency", value: settings.currencyCode)
        }
    }

    private var calculationSection: some View {
        Section {
            Picker("settings.rate.mode", selection: Binding(
                get: { settings.rateMode },
                set: { settings.rateMode = $0; dependencies.settingsStore.save() }
            )) {
                Text("rate.official").tag(RateMode.official)
                Text("rate.employer").tag(RateMode.employer)
                Text("rate.custom").tag(RateMode.custom)
            }

            if settings.rateMode != .official {
                HStack {
                    Text(settings.rateMode == .employer ? "settings.rate.employer" : "settings.rate.custom")
                    Spacer()
                    TextField("0.00", value: Binding(
                        get: { settings.rateMode == .employer ? settings.employerRate : settings.customRate },
                        set: { newValue in
                            if settings.rateMode == .employer { settings.employerRate = newValue } else { settings.customRate = newValue }
                            dependencies.settingsStore.save()
                        }
                    ), format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    Text("/\(Fmt.unitAbbreviation(settings.distanceUnit, locale: locale))")
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            LabeledContent("settings.active.rule") {
                Text(dependencies.activeRuleDescription())
                    .multilineTextAlignment(.trailing)
                    .scaledFont(13, relativeTo: .footnote)
            }

            if let source = dependencies.activeRuleSource() {
                Button("settings.rule.source") { openURL(source) }
                    .scaledFont(14, relativeTo: .subheadline)
            }
        } header: {
            Text("settings.calculation")
        } footer: {
            if !dependencies.hasOfficialRule() {
                // Being explicit beats quietly producing a number: this country has no
                // verified scale in the app, and the report will say so too.
                Text("settings.no.official.rule")
            }
        }
    }

    /// Two switches for two reminders. Both were decided once, at onboarding, and never
    /// again: the trip reminder is the one thing that catches a trip left running overnight,
    /// and a user who tapped Skip could not turn it on from anywhere.
    private var notificationsSection: some View {
        Section {
            if settings.notificationsEnabled {
                Toggle("settings.notifications.trip", isOn: Binding(
                    get: { settings.tripReminderEnabled },
                    set: { settings.tripReminderEnabled = $0; dependencies.applyNotificationPreferences() }
                ))
                Toggle("settings.notifications.report", isOn: Binding(
                    get: { settings.monthlyReportReminderEnabled },
                    set: { settings.monthlyReportReminderEnabled = $0; dependencies.applyNotificationPreferences() }
                ))
            } else {
                Button("onboarding.notifications.allow") {
                    Task { await dependencies.requestNotificationPermission() }
                }
                .foregroundStyle(Theme.signal)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("settings.notifications.open", destination: url)
                }
            }
        } header: {
            Text("settings.notifications")
        } footer: {
            Text(settings.notificationsEnabled ? "settings.notifications.trip.help" : "settings.notifications.denied")
        }
    }

    private var dataSection: some View {
        Section {
            Toggle("settings.icloud", isOn: Binding(
                get: { settings.iCloudSyncEnabled && CloudKitAvailability.isEntitled },
                set: { settings.iCloudSyncEnabled = $0; dependencies.settingsStore.save() }
            ))
            // Shown as off and disabled rather than on-and-doing-nothing: a sync switch that
            // lies about syncing is how someone loses data they believed was backed up.
            .disabled(!CloudKitAvailability.isEntitled)
            Button("settings.export.all") {
                if let url = dependencies.exportAllData() {
                    exportFile = ExportedFile(url: url)
                } else {
                    // Silence used to be the failure mode: the sheet simply never appeared.
                    exportFailed = true
                }
            }
            Button("settings.delete.all", role: .destructive) { showsDeleteConfirmation = true }
        } header: {
            Text("settings.data")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !CloudKitAvailability.isEntitled {
                    Text("settings.icloud.unavailable")
                }
                Text("settings.export.all.note")
            }
        }
    }

    private var subscriptionSection: some View {
        Section("settings.subscription") {
            LabeledContent("settings.plan", value: dependencies.subscriptionDescription())
            if dependencies.subscriptions.entitlement.isActive {
                Link("settings.manage", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            } else {
                Button("settings.subscribe") { showsPaywall = true }
            }
            Button("paywall.restore") { Task { try? await dependencies.subscriptions.restore() } }
        }
    }

    private var aboutSection: some View {
        Section("settings.about") {
            if let privacy = AppLinks.privacy { Link("paywall.privacy", destination: privacy) }
            if let terms = AppLinks.terms { Link("paywall.terms", destination: terms) }
            if let support = AppLinks.support { Link("settings.support", destination: support) }
            LabeledContent("settings.version", value: dependencies.versionString)
        }
    }
}

struct CountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Binding var selection: String
    @State private var search = ""

    private var countries: [CountryInfo] {
        let all = CountryCatalog.all(locale: locale)
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(countries) { country in
                Button {
                    selection = country.code
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag)
                        Text(country.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if country.code == selection {
                            Image(systemName: "checkmark").foregroundStyle(Theme.signal)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: Text("settings.country.search"))
            .navigationTitle("settings.country")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
