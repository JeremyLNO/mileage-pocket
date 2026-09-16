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

/// The app on the home screen.
///
/// Small and medium: the same three faces, the medium one with room for the month's figures
/// alongside whatever is being asked. `.systemSmall` alone meant the queue count and the
/// month total could never appear together.
struct StartTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StartTripWidget", provider: StartTripProvider()) { entry in
            TripStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("app.name")
        .description("widget.start.trip")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
