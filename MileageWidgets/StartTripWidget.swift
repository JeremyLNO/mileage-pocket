import SwiftUI
import WidgetKit

struct StartTripEntry: TimelineEntry {
    let date: Date
}

struct StartTripProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartTripEntry { StartTripEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (StartTripEntry) -> Void) {
        completion(StartTripEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartTripEntry>) -> Void) {
        completion(Timeline(entries: [StartTripEntry(date: .now)], policy: .never))
    }
}

struct StartTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StartTripWidget", provider: StartTripProvider()) { _ in
            VStack {
                Image(systemName: "car.fill")
                Text(verbatim: "Start Trip")
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}
