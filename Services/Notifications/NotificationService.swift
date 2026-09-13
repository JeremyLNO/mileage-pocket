import Foundation
import UserNotifications

/// Three notifications, all of them optional, none of them marketing.
///
/// The one that earns its place is the long-running-trip reminder: forgetting to press STOP
/// is the failure mode that silently ruins a month of records.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    enum Identifier {
        static let tripStillRunning = "trip.still.running"
        static let monthlyReport = "monthly.report"
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        await center.notificationSettings().authorizationStatus == .authorized
    }

    /// Fires three hours into a trip. Long enough not to nag a real long drive, short enough
    /// that a trip left running overnight is caught the same day.
    func scheduleTripStillRunningReminder(after interval: TimeInterval = 3 * 3600) {
        let content = UNMutableNotificationContent()
        content.title = L.string("notification.trip.running.title")
        content.body = L.string("notification.trip.running.body")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Identifier.tripStillRunning,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.add(request)
    }

    func cancelTripReminders() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.tripStillRunning])
    }

    func notifyTripSaved(distanceText: String) {
        let content = UNMutableNotificationContent()
        content.title = L.string("notification.trip.saved.title")
        content.body = L.format("notification.trip.saved.body", distanceText)
        content.sound = nil
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// The 1st of each month at 09:00: the moment a monthly report is worth producing.
    func scheduleMonthlyReportReminder() {
        var components = DateComponents()
        components.day = 1
        components.hour = 9

        let content = UNMutableNotificationContent()
        content.title = L.string("notification.report.title")
        content.body = L.string("notification.report.body")
        content.sound = .default

        center.add(UNNotificationRequest(
            identifier: Identifier.monthlyReport,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    func cancelMonthlyReportReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.monthlyReport])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
