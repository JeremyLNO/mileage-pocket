import SwiftUI
import WidgetKit

struct StartTripEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StartTripProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartTripEntry {
        StartTripEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StartTripEntry) -> Void) {
        // The placeholder carries invented figures — 486 km, a euro amount — which belong in
        // the gallery and nowhere else. Outside a preview a missing snapshot means the user
        // has not driven yet, and the widget has to say so rather than show someone else's
        // month.
        let snapshot: WidgetSnapshot? = context.isPreview ? WidgetSnapshot.placeholder : WidgetSnapshotStore.read()
        completion(StartTripEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartTripEntry>) -> Void) {
        let entry = StartTripEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // The app reloads timelines whenever a trip ends, so there is nothing for the widget
        // itself to poll for; refreshing hourly only guards against a missed reload.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// A small widget with one job: get the user into a running trip before they pull away.
struct StartTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StartTripWidget", provider: StartTripProvider()) { entry in
            StartTripWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("app.name")
        .description("widget.start.trip")
        .supportedFamilies([.systemSmall])
    }
}

struct StartTripWidgetView: View {
    let entry: StartTripEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: entry.snapshot?.isTripInProgress == true ? "record.circle" : "car.side.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.snapshot?.isTripInProgress == true ? "activity.title" : "widget.start.trip")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.orange)

            Spacer(minLength: 6)

            if let snapshot = entry.snapshot {
                Text(snapshot.monthLabel)
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value(for: snapshot))
                        .font(.system(size: 30, weight: .medium, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(snapshot.unit == .kilometers ? "km" : "mi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let amount = snapshot.formattedAmount {
                    Text(amount)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("home.empty.title")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "mileagepocket://start"))
    }

    private func value(for snapshot: WidgetSnapshot) -> String {
        let distance = snapshot.unit.value(fromMeters: snapshot.distanceMeters)
        return distance.formatted(.number.precision(.fractionLength(0)))
    }
}
