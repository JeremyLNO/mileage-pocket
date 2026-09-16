import AppIntents
import SwiftUI
import WidgetKit

/// One frame of the widget's timeline.
///
/// Here rather than beside the provider so the faces below can be rendered — and looked at —
/// from a test. A widget extension has no test target of its own, and a design nobody has
/// seen is a design nobody has checked.
struct StartTripEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// What the widget puts in front of the reader.
///
/// One rule decides everything: a drive under way beats a queue, and a queue beats figures
/// nobody has to act on. The month is what shows when there is nothing to do — which is most
/// days, and is why the idle faces are the ones worth designing.
///
/// Two of the three states carry buttons, and each does exactly what it says. Business and
/// Personal run in the extension's process and record the answer — see `QualifyTripIntent`;
/// the app applies it, because pricing a trip re-prices the tax year and that cannot be done
/// from here. STOP opens the app, deliberately: ending a drive means closing the route and
/// stopping the location manager, neither of which exists in this process. A STOP drawn here
/// that only *looked* like it stopped would be the kind of control this app spends its time
/// removing.
///
/// The three sizes are one design at three scales, not three drawings: the same tile, the
/// same tinted disc, the same way of setting a figure — see `WidgetChrome`.
struct TripStatusWidgetView: View {
    let entry: StartTripEntry
    /// Set only when a test renders a face at a chosen size. The widget itself never passes
    /// it and reads the environment, as WidgetKit intends — `widgetFamily` is a read-only
    /// environment value, so there is no way to render a large face off the home screen
    /// without a seam like this one, and a design nobody has seen is a design nobody has
    /// checked.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var figures: WidgetFigures? { snapshot?.figures }

    /// Resolved in the app's chosen language, carried on the snapshot.
    private var t: LocalizedStrings {
        LocalizedStrings(languageCode: snapshot?.languageCode ?? "en")
    }

    /// The app's locale, carried on the snapshot. Every number below is set in it — left to
    /// itself the extension formats in the *system* locale, and the home screen then spells
    /// the month's distance differently from the app it opens.
    private var locale: Locale { snapshot?.locale ?? .current }

    /// The trip the buttons act on. When the queue is longer than the snapshot carries, this
    /// runs out before the count does — and the face falls back to one that only opens the
    /// app, rather than offering to classify a trip it cannot name.
    private var askable: PendingTrip? { snapshot?.pending.first }

    var body: some View {
        Group {
            switch family {
            case .systemLarge: large
            case .systemMedium: medium
            default: small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Buttons take their own taps; the rest of the face opens the app where its own
        // headline pointed.
        .widgetURL(snapshot?.destination ?? URL(string: "mileagepocket://start"))
    }

    // MARK: - Small

    private var small: some View {
        WidgetTile {
            switch snapshot?.focus {
            case .recording:
                VStack(alignment: .leading, spacing: 0) {
                    recordingHead(timerSize: 26)
                    Spacer(minLength: 6)
                    stopButton
                }
            case .awaitingReview(let count):
                VStack(alignment: .leading, spacing: 0) {
                    queueHead(count, titleSize: 14)
                    Spacer(minLength: 6)
                    if let askable { qualifyButtons(for: askable) }
                }
            case .month, .none:
                VStack(alignment: .leading, spacing: 6) {
                    todayHead
                    RoadIllustration().frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Medium

    private var medium: some View {
        WidgetTile(padding: 12) {
            switch snapshot?.focus {
            case .recording:
                HStack(spacing: 12) {
                    recordingHead(timerSize: 32)
                    stopButton.frame(width: 124)
                }
            case .awaitingReview(let count):
                VStack(alignment: .leading, spacing: 0) {
                    queueHead(count, titleSize: 17)
                    Spacer(minLength: 8)
                    if let askable { qualifyButtons(for: askable) }
                }
            case .month, .none:
                monthPanel
            }
        }
    }

    /// The month as the design sets it: the total driven, how many drives made it, and the
    /// one proportion a mileage log exists to establish.
    private var monthPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetTileHeader(systemImage: "calendar", title: monthTitle, tint: Theme.personal)
            Spacer(minLength: 2)
            WidgetFigure(value: monthValue, unit: unitAbbreviation, size: 34)
            if let figures {
                Text(t.plural("widget.trips.count", figures.monthTripCount))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            if let share = figures?.businessShare {
                WidgetSplitBar(businessShare: share)
                Spacer(minLength: 6)
                WidgetSplitLegend(
                    businessShare: share,
                    businessLabel: t("trip.type.business"),
                    personalLabel: t("trip.type.personal"),
                    locale: locale
                )
            } else if let amount = snapshot?.formattedAmount {
                // Nothing driven this month, so there is no proportion to draw — but there
                // may still be a figure worth showing.
                Text(amount)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Large

    private var large: some View {
        VStack(spacing: WidgetChrome.tileSpacing) {
            HStack(spacing: WidgetChrome.tileSpacing) {
                todayOrRecordingTile
                monthTile
            }
            HStack(spacing: WidgetChrome.tileSpacing) {
                reimbursementTile
                latestTripTile
            }
            // The band is where action lives. Decoration only gets it when the app is asking
            // for nothing — a road drawn over a trip waiting to be classified would be the
            // widget admiring itself. It is also why the band is taller when idle: a picture
            // wants room, a button wants to be the size of a thumb.
            band.frame(height: isIdle ? 132 : 82)
        }
    }

    private var todayOrRecordingTile: some View {
        WidgetTile {
            if snapshot?.focus == .recording {
                recordingHead(timerSize: 26)
            } else {
                todayHead
            }
        }
    }

    private var monthTile: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 2) {
                WidgetTileHeader(systemImage: "calendar", title: monthTitle, tint: Theme.personal)
                WidgetFigure(value: monthValue, unit: unitAbbreviation, size: 26)
                if let figures {
                    Text(t.plural("widget.trips.count", figures.monthTripCount))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var reimbursementTile: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 2) {
                WidgetTileHeader(systemImage: "banknote.fill", title: t("widget.reimbursement"), tint: Theme.business)
                WidgetFigure(value: snapshot?.formattedAmount ?? "—", size: 24)
                // Only when one rate really does apply to the whole month. Under a tiered
                // scale there is no such number, and printing one invites the reader to
                // check an arithmetic that was never performed.
                if let rate = figures?.formattedRate {
                    Text(t.format("widget.rate.basis", rate))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var latestTripTile: some View {
        WidgetTile {
            VStack(alignment: .leading, spacing: 4) {
                WidgetTileHeader(systemImage: "mappin.and.ellipse", title: t("widget.latest.trip"), tint: Theme.personal)
                if let trip = figures?.lastTrip {
                    let tint = trip.isBusiness ? Theme.business : Theme.personal
                    VStack(alignment: .leading, spacing: 2) {
                        endpoint(trip.start, tint: tint, filled: false)
                        endpoint(trip.end, tint: tint, filled: true)
                    }
                    Text("\(trip.distanceText)  ·  \(trip.durationText)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(t("home.empty.title"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func endpoint(_ name: String, tint: Color, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? tint : Color.clear)
                .overlay(Circle().strokeBorder(tint, lineWidth: 1.6))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var isIdle: Bool {
        switch snapshot?.focus {
        case .recording, .awaitingReview: return false
        case .month, .none: return true
        }
    }

    @ViewBuilder
    private var band: some View {
        switch snapshot?.focus {
        case .recording:
            WidgetTile { stopButton }
        case .awaitingReview:
            WidgetTile {
                if let askable {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(askable.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        qualifyButtons(for: askable)
                    }
                } else {
                    Text(t("widget.review.cta"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        case .month, .none:
            RoadIllustration()
        }
    }

    // MARK: - Shared heads

    private var todayHead: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetTileHeader(systemImage: "car.side.fill", title: t("widget.today"), tint: Theme.signal)
            WidgetFigure(
                value: distanceValue(figures?.todayDistanceMeters ?? 0),
                unit: unitAbbreviation,
                size: family == .systemSmall ? 34 : 26
            )
            // Drawn only when there is a yesterday to compare against.
            if let change = figures?.dayChange {
                WidgetTrend(change: change, label: t("widget.vs.yesterday"), locale: locale)
            }
        }
    }

    private func recordingHead(timerSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetTileHeader(systemImage: "record.circle", title: t("widget.recording"), tint: Theme.stop)
            if let startedAt = snapshot?.tripStartedAt {
                // The widget runs its own clock from the start date rather than showing a
                // duration frozen at whatever the last write happened to be.
                Text(startedAt, style: .timer)
                    .font(.system(size: timerSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let snapshot, let meters = snapshot.tripDistanceMeters {
                Text(distanceText(meters))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func queueHead(_ count: Int, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetTileHeader(
                systemImage: "questionmark.circle.fill",
                title: t.plural("trips.review.count", count),
                tint: Theme.signal
            )
            if let askable {
                // The trip is named before it is judged. Two buttons under "Business or
                // personal?" would be asking about a drive the reader cannot identify.
                Text(askable.label)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(askable.distanceText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(t("widget.review.cta"))
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: - Controls

    private var stopButton: some View {
        Button(intent: StopTripIntent(tripStartedAt: snapshot?.tripStartedAt)) {
            Text(t("activetrip.stop"))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.stop)
                // A fixed height, not "whatever is left": grown to fill, STOP became a red
                // field with a word in the middle of it on the small face.
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Theme.stop.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func qualifyButtons(for trip: PendingTrip) -> some View {
        HStack(spacing: 6) {
            qualifyButton(trip: trip, isBusiness: true, title: t("trip.type.business"), tint: Theme.business)
            qualifyButton(trip: trip, isBusiness: false, title: t("trip.type.personal"), tint: Theme.personal)
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
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Figures

    /// "This month", not "September".
    ///
    /// The widget refreshes on its own schedule, so between midnight on the 1st and the next
    /// reload a month *name* is simply wrong while "this month" never is — and the figure
    /// underneath always covers the month the reader is in.
    private var monthTitle: String { t("widget.month.title") }

    /// The month's total — every drive, not only the claimable ones. The split bar under it
    /// is what separates the two, and a headline that silently excluded personal trips would
    /// make that bar describe a different month than the number above it.
    private var monthValue: String {
        distanceValue(figures?.monthTotalMeters ?? snapshot?.distanceMeters ?? 0)
    }

    private var unitAbbreviation: String {
        DistanceDisplay.unitAbbreviation(snapshot?.unit ?? .kilometers, locale: locale)
    }

    private func distanceValue(_ meters: Double) -> String {
        DistanceDisplay.value(
            meters: meters,
            unit: snapshot?.unit ?? .kilometers,
            locale: locale,
            fractionDigits: 0
        )
    }

    private func distanceText(_ meters: Double) -> String {
        "\(distanceValue(meters)) \(unitAbbreviation)"
    }
}
