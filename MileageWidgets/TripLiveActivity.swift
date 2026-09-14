import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen and Dynamic Island presentation for a trip in progress.
///
/// The compact leading/trailing slots get the two numbers that matter — elapsed time and
/// distance — because that is the whole question being asked from the driver's seat.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.startedAt, style: .timer).monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.system(size: 15, weight: .medium))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(distanceText(context.state))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label(context.attributes.vehicleName, systemImage: "car.side.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "car.side.fill")
            } compactTrailing: {
                Text(distanceText(context.state))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            } minimal: {
                Image(systemName: "car.side.fill")
            }
            .keylineTint(.orange)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<TripAttributes>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("activity.title")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.orange)
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(distanceText(context.state))
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                Text(context.attributes.vehicleName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    /// The same call the app makes, from the same file. Writing this a second time here —
    /// `String(format: "%.1f")`, which always uses a dot and rounds by its own rules — is how
    /// the lock screen and the driving screen came to disagree about one drive.
    private func distanceText(_ state: TripAttributes.ContentState) -> String {
        DistanceDisplay.text(meters: state.distanceMeters, unit: state.unit, locale: state.locale)
    }
}
