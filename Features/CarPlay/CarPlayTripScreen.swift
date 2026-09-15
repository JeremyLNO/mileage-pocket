import Foundation

/// What the car's screen shows, as plain values.
///
/// Separated from `CPInformationTemplate` on purpose: CarPlay cannot be driven from a test
/// — there is no way to attach a head unit to a simulator from a command line — so the part
/// that can be got wrong is pulled out of the part that cannot be exercised. Everything a
/// driver reads at 110 km/h is decided here, and tested.
struct CarPlayTripScreen: Equatable {
    struct Row: Equatable {
        let title: String
        let detail: String
    }

    /// What the button does when pressed. `.none` draws no button at all: a control that
    /// looks pressable and does nothing is worse at the wheel than no control.
    enum Action: Equatable {
        case start
        case stop
        case none
    }

    let rows: [Row]
    let action: Action
    let actionTitle: String?

    /// - Parameters:
    ///   - canStart: whether access allows a new trip. A paywall cannot be shown on a car
    ///     screen, so when it does not, the screen says where to go instead of offering a
    ///     button that would silently fail.
    ///   - canRecordFromCar: whether location is authorised **Always**.
    ///
    ///     This is not a nicety either. "While Using" permits background updates for a
    ///     session that *began* while the app was in use; a session started from the car
    ///     screen, phone locked, did not. iOS then withholds every position: the clock runs,
    ///     the distance stays at 0.0 km, and the app looks like it is working. Offering
    ///     START in that state is the one thing this screen must not do.
    static func make(
        isRecording: Bool,
        isPaused: Bool,
        canStart: Bool,
        canRecordFromCar: Bool = true,
        distanceMeters: Double,
        startedAt: Date?,
        vehicleName: String?,
        unit: DistanceUnit,
        locale: Locale,
        now: Date
    ) -> CarPlayTripScreen {
        var rows: [Row] = []

        if isRecording {
            rows.append(Row(
                title: L.string("carplay.status"),
                detail: L.string(isPaused ? "carplay.paused" : "carplay.recording")
            ))
            rows.append(Row(
                title: L.string("reports.distance"),
                detail: Fmt.distance(meters: distanceMeters, unit: unit, locale: locale)
            ))
            // Measured from the start, not from the last movement: a clock that resets at
            // every red light is worse than no clock.
            let elapsed = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
            rows.append(Row(
                title: L.string("detail.duration"),
                detail: Fmt.duration(elapsed, locale: locale)
            ))
        } else if !canRecordFromCar {
            rows.append(Row(
                title: L.string("carplay.status"),
                detail: L.string("carplay.needs.always")
            ))
            rows.append(Row(
                title: "",
                detail: L.string("carplay.needs.always.detail")
            ))
        } else if canStart {
            rows.append(Row(
                title: L.string("carplay.status"),
                detail: L.string("carplay.ready")
            ))
            rows.append(Row(
                title: L.string("detail.vehicle"),
                detail: vehicleName ?? L.string("home.no.vehicle")
            ))
            rows.append(Row(
                title: "",
                detail: L.string("carplay.ready.detail")
            ))
        } else {
            rows.append(Row(
                title: L.string("carplay.status"),
                detail: L.string("carplay.locked")
            ))
            rows.append(Row(
                title: "",
                detail: L.string("carplay.locked.detail")
            ))
        }

        if isRecording {
            return CarPlayTripScreen(rows: rows, action: .stop, actionTitle: L.string("activetrip.stop.accessibility"))
        }
        if canStart, canRecordFromCar {
            return CarPlayTripScreen(rows: rows, action: .start, actionTitle: L.string("home.start.accessibility"))
        }
        return CarPlayTripScreen(rows: rows, action: .none, actionTitle: nil)
    }
}
