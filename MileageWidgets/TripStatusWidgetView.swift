import AppIntents
import SwiftUI
import WidgetKit

/// What the widget puts in front of the reader.
///
/// One rule decides everything here: a drive under way beats a queue, and a queue beats a
/// monthly total nobody taps. The total is the third thing shown, not the first, because
/// it is the one figure that asks nothing of anybody.
///
/// Two of the three faces carry buttons, and each one does exactly what it says. Business
/// and Personal run in the extension's process and record the answer — see
/// `QualifyTripIntent`; the app applies it, because pricing a trip re-prices the tax year
/// and that cannot be done from here. STOP opens the app, deliberately: ending a drive means
/// closing the route and stopping the location manager, neither of which exists in this
/// process. A STOP drawn here that only *looked* like it stopped would be exactly the kind
/// of control this app has spent its time removing.
struct TripStatusWidgetView: View {
    let entry: StartTripEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    /// Resolved in the app's chosen language, carried on the snapshot.
    private var t: LocalizedStrings {
        LocalizedStrings(languageCode: snapshot?.languageCode ?? "en")
    }

    /// The trip the buttons act on. When the queue is longer than the snapshot carries, this
    /// runs out before the count does — and the face falls back to the one that only opens
    /// the app, rather than offering to classify a trip it cannot name.
    private var askable: PendingTrip? { snapshot?.pending.first }

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
        // Buttons handle their own taps; the rest of the face opens the app where its
        // headline pointed.
        .widgetURL(snapshot?.destination ?? URL(string: "mileagepocket://start"))
    }

    // MARK: - Faces

    private var recording: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(t("widget.recording"), systemImage: "record.circle", tint: .red)
            Spacer(minLength: 4)
            if let startedAt = snapshot?.tripStartedAt {
                // The widget runs its own clock from the start date rather than showing a
                // duration frozen at whatever the last write happened to be.
                Text(startedAt, style: .timer)
                    .font(.system(size: family == .systemSmall ? 24 : 30, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let snapshot, let meters = snapshot.tripDistanceMeters {
                Text(distanceText(meters, unit: snapshot.unit))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button(intent: StopTripIntent(tripStartedAt: snapshot?.tripStartedAt)) {
                Text(t("activetrip.stop"))
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func awaitingReview(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(t.plural("trips.review.count", count), systemImage: "questionmark.circle.fill", tint: .orange)
            Spacer(minLength: 4)
            if let askable {
                // The trip is named before it is judged. "Business or personal?" above two
                // buttons and nothing else would be asking about a drive the reader has no
                // way to identify.
                Text(askable.label)
                    .font(.system(size: family == .systemSmall ? 14 : 16, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(askable.distanceText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                qualificationButtons(for: askable)
            } else {
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

    private func qualificationButtons(for trip: PendingTrip) -> some View {
        HStack(spacing: 6) {
            qualifyButton(trip: trip, isBusiness: true, title: t("trip.type.business"), tint: .orange)
            qualifyButton(trip: trip, isBusiness: false, title: t("trip.type.personal"), tint: .secondary)
        }
    }

    private func qualifyButton(trip: PendingTrip, isBusiness: Bool, title: String, tint: Color) -> some View {
        Button(intent: QualifyTripIntent(tripID: trip.id, isBusiness: isBusiness)) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                // "Professionnel" is three times the width of "Business"; the button shrinks
                // its text rather than truncating a word the reader has to guess at.
                .minimumScaleFactor(0.55)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

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
