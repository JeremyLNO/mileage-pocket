import SwiftUI
import WidgetKit

/// What the widget puts in front of the reader.
///
/// One rule decides everything here: a drive under way beats a queue, and a queue beats a
/// monthly total nobody taps. The total is the third thing shown, not the first, because
/// it is the one figure that asks nothing of anybody.
///
/// Nothing in here mutates state. A widget's buttons run in the *extension's* process, which
/// can reach neither the recorder nor the app's store — a STOP drawn here would be a control
/// that does nothing, and this app has spent enough time removing those. So every face ends
/// in a tap that opens the app exactly where its own headline pointed.
struct TripStatusWidgetView: View {
    let entry: StartTripEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    /// Resolved in the app's chosen language, carried on the snapshot.
    private var t: LocalizedStrings {
        LocalizedStrings(languageCode: snapshot?.languageCode ?? "en")
    }

    var body: some View {
        Group {
            switch snapshot?.focus {
            case .recording:
                recording
            case .awaitingReview(let count):
                awaitingReview(count)
            case .month, .none:
                month
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(snapshot?.destination ?? URL(string: "mileagepocket://start"))
    }

    // MARK: - Faces

    private var recording: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(t("widget.recording"), systemImage: "record.circle", tint: .red)
            Spacer(minLength: 6)
            if let startedAt = snapshot?.tripStartedAt {
                // The widget runs its own clock from the start date rather than showing a
                // duration frozen at whatever the last write happened to be.
                Text(startedAt, style: .timer)
                    .font(.system(size: family == .systemSmall ? 26 : 32, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let snapshot, let meters = snapshot.tripDistanceMeters {
                Text(distanceText(meters, unit: snapshot.unit))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func awaitingReview(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(t.plural("trips.review.count", count), systemImage: "questionmark.circle.fill", tint: .orange)
            Spacer(minLength: 6)
            Text(t("widget.review.cta"))
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if family != .systemSmall, let snapshot {
                Spacer(minLength: 6)
                monthLine(snapshot)
            }
        }
    }

    private var month: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(t("widget.month.title"), systemImage: "car.side.fill", tint: .orange)
            Spacer(minLength: 6)
            if let snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(distanceValue(snapshot.distanceMeters, unit: snapshot.unit))
                        .font(.system(size: family == .systemSmall ? 30 : 36, weight: .medium, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(snapshot.unit == .kilometers ? "km" : "mi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if let amount = snapshot.formattedAmount {
                    Text(amount)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                // No snapshot at all: the app has never finished a trip on this device.
                Text(t("home.empty.title"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pieces

    private func header(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
    }

    private func monthLine(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            Text(snapshot.monthLabel)
                .textCase(.uppercase)
            Text(distanceText(snapshot.distanceMeters, unit: snapshot.unit))
            if let amount = snapshot.formattedAmount {
                Text("·")
                Text(amount)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func distanceValue(_ meters: Double, unit: DistanceUnit) -> String {
        unit.value(fromMeters: meters).formatted(.number.precision(.fractionLength(0)))
    }

    private func distanceText(_ meters: Double, unit: DistanceUnit) -> String {
        "\(distanceValue(meters, unit: unit)) \(unit == .kilometers ? "km" : "mi")"
    }
}
