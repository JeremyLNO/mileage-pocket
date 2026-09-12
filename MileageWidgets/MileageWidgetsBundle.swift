import SwiftUI
import WidgetKit

@main
struct MileageWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StartTripWidget()
        TripLiveActivity()
    }
}
