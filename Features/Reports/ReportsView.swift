import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]

    @State private var selection: PeriodKind = .month
    /// How many periods back from the current one is on screen. A mileage claim is filed
    /// after the period it covers has ended — in April for last year, on the 3rd for last
    /// month — and the screen only ever showed the period in progress, which is the one
    /// nobody exports.
    @State private var periodsBack = 0
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var exportURL: ExportedFile?
    @State private var showsPaywall = false
    @State private var isExporting = false
    @State private var exportFailed = false

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
            let date = calendar.date(byAdding: .month, value: -periodsBack, to: now) ?? now
            return .month(year: calendar.component(.year, from: date), month: calendar.component(.month, from: date))
        case .quarter:
            let date = calendar.date(byAdding: .month, value: -3 * periodsBack, to: now) ?? now
            let quarter = (calendar.component(.month, from: date) - 1) / 3 + 1
            return .quarter(year: calendar.component(.year, from: date), quarter: quarter)
        case .year:
            return .year(calendar.component(.year, from: now) - periodsBack)
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
            .alert("export.failed.title", isPresented: $exportFailed) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("export.failed.message")
            }
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
            .onChange(of: selection) { _, _ in periodsBack = 0 }

            if selection != .custom {
                periodStepper
            }

            if selection == .custom {
                DatePicker("reports.from", selection: $customStart, displayedComponents: .date)
                DatePicker("reports.to", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
        }
    }

    /// Walks back through finished periods. There is no forward past the current one: a
    /// report for a month that has not happened is an empty document with a confusing title.
    private var periodStepper: some View {
        HStack {
            Button {
                periodsBack += 1
            } label: {
                Image(systemName: "chevron.left")
                    .scaledFont(15, relativeTo: .subheadline, weight: .semibold)
                    .frame(width: 44, height: 34)
            }
            .accessibilityLabel(Text(L.string("reports.previous")))

            Spacer()

            Text(period.title(locale: locale))
                .scaledFont(15, relativeTo: .subheadline, weight: .semibold)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button {
                periodsBack = max(0, periodsBack - 1)
            } label: {
                Image(systemName: "chevron.right")
                    .scaledFont(15, relativeTo: .subheadline, weight: .semibold)
                    .frame(width: 44, height: 34)
            }
            .accessibilityLabel(Text(L.string("reports.next")))
            .disabled(periodsBack == 0)
        }
        .tint(Theme.signal)
        .accessibilityIdentifier("reportPeriodStepper")
    }

    private var summary: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(period.title(locale: locale))
                    .scaledFont(22, relativeTo: .title2, weight: .bold)
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
                    .scaledFont(13, relativeTo: .footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func export(_ format: ExportFormat) {
        guard dependencies.canAccess(.exportReport) else {
            showsPaywall = true
            return
        }
        isExporting = true
        defer { isExporting = false }
        if let url = dependencies.export(data, format: format) {
            exportURL = ExportedFile(url: url)
        } else {
            // A failed export used to do nothing at all: no sheet, no message, no clue.
            exportFailed = true
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
