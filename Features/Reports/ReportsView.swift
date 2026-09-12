import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]

    @State private var selection: PeriodKind = .month
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var exportURL: ExportedFile?
    @State private var showsPaywall = false
    @State private var isExporting = false

    private enum PeriodKind: String, CaseIterable, Identifiable {
        case month, quarter, year, custom
        var id: String { rawValue }
        var titleKey: LocalizedStringKey {
            switch self {
            case .month: return "reports.period.month"
            case .quarter: return "reports.period.quarter"
            case .year: return "reports.period.year"
            case .custom: return "reports.period.custom"
            }
        }
    }

    private var settings: UserSettings { dependencies.settingsStore.settings }

    private var period: ReportPeriod {
        let calendar = Calendar.current
        let now = Date.now
        switch selection {
        case .month:
            return .month(year: calendar.component(.year, from: now), month: calendar.component(.month, from: now))
        case .quarter:
            let quarter = (calendar.component(.month, from: now) - 1) / 3 + 1
            return .quarter(year: calendar.component(.year, from: now), quarter: quarter)
        case .year:
            return .year(calendar.component(.year, from: now))
        case .custom:
            return .custom(start: customStart, end: customEnd)
        }
    }

    private var data: ReportData {
        ReportBuilder.build(
            trips: trips.filter { $0.endedAt != nil },
            period: period,
            calendar: .current,
            vehicleNames: dependencies.vehicleNames(),
            fallbackCurrency: settings.currencyCode
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    periodPicker
                    summary
                    exportButtons
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("tab.reports")
            .sheet(item: $exportURL) { file in
                ShareSheet(url: file.url)
            }
            .sheet(isPresented: $showsPaywall) { PaywallView() }
        }
    }

    private var periodPicker: some View {
        VStack(spacing: 12) {
            Picker("reports.period", selection: $selection) {
                ForEach(PeriodKind.allCases) { kind in
                    Text(kind.titleKey).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if selection == .custom {
                DatePicker("reports.from", selection: $customStart, displayedComponents: .date)
                DatePicker("reports.to", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
        }
    }

    private var summary: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(period.title(locale: locale))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 12) {
                    StatTile(label: "reports.trips", value: "\(data.businessTripCount)")
                    StatTile(
                        label: "reports.distance",
                        value: Fmt.distance(meters: data.totalDistanceMeters, unit: settings.distanceUnit, locale: locale)
                    )
                    StatTile(
                        label: "reports.total",
                        value: Fmt.money(data.totalAmount, currencyCode: data.currencyCode, locale: locale)
                    )
                }
            }
        }
    }

    private var exportButtons: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "reports.generate", systemImage: "doc.richtext", isEnabled: !isExporting) {
                export(.pdf)
            }
            SecondaryButton(title: "reports.csv") { export(.csv) }
            if data.isEmpty {
                Text("reports.empty.hint")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func export(_ format: ExportFormat) {
        guard dependencies.subscriptions.canAccess(.exportReport) else {
            showsPaywall = true
            return
        }
        isExporting = true
        defer { isExporting = false }
        if let url = dependencies.export(data, format: format) {
            exportURL = ExportedFile(url: url)
        }
    }
}

enum ExportFormat { case pdf, csv }

struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Thin wrapper around the system share sheet; `ShareLink` cannot present a file produced
/// on demand at tap time without rendering it up front for every period.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
