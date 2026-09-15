import CarPlay
import Foundation

/// The app's face on the car's screen.
///
/// One template, three rows and one button. A CarPlay "driving task" app is allowed exactly
/// that, and it is also all a mileage log needs: the whole task is pressing Start before
/// pulling away and Stop on arrival — which is precisely what a driver forgets, and what
/// they should not be reaching for a phone to do.
///
/// UIKit builds this object itself, from the scene manifest, so it cannot be handed its
/// dependencies. `AppDependencies.current` is the narrow escape hatch for exactly that, and
/// nothing else in the app uses it.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var template: CPInformationTemplate?
    private var timer: Timer?
    private var shown: CarPlayTripScreen?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        MainActor.assumeIsolated {
            let template = CPInformationTemplate(
                title: L.string("app.name"), layout: .leading, items: [], actions: []
            )
            self.template = template
            interfaceController.setRootTemplate(template, animated: false, completion: nil)
            refresh()
            // The distance and the clock both move while the app is otherwise idle, so the
            // screen is rebuilt on a tick rather than only on a recorder callback.
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { self.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        timer?.invalidate()
        timer = nil
        self.interfaceController = nil
        template = nil
        shown = nil
    }

    // MARK: - Rendering

    @MainActor
    private func refresh() {
        guard let template, let dependencies = AppDependencies.current else { return }
        let screen = CarPlayTripScreen.make(
            isRecording: dependencies.isRecording,
            isPaused: dependencies.isTripPaused,
            canStart: dependencies.canAccess(.startTrip),
            canRecordFromCar: dependencies.recorder.authorizationStatus == .authorizedAlways,
            distanceMeters: dependencies.activeDistanceMeters,
            startedAt: dependencies.activeStartedAt,
            vehicleName: dependencies.activeVehicleName,
            unit: dependencies.settingsStore.settings.distanceUnit,
            locale: dependencies.localization.locale,
            now: .now
        )
        // Nothing redrawn when nothing changed: CarPlay animates every assignment, and a
        // template rebuilt once a second flickers for the whole drive.
        guard screen != shown else { return }
        shown = screen

        template.items = screen.rows.map {
            CPInformationItem(title: $0.title.isEmpty ? nil : $0.title, detail: $0.detail)
        }
        template.actions = Self.buttons(for: screen)
    }

    @MainActor
    private static func buttons(for screen: CarPlayTripScreen) -> [CPTextButton] {
        guard let title = screen.actionTitle else { return [] }
        switch screen.action {
        case .start:
            return [CPTextButton(title: title, textStyle: .confirm) { _ in
                MainActor.assumeIsolated { AppDependencies.current?.startTrip() }
            }]
        case .stop:
            return [CPTextButton(title: title, textStyle: .cancel) { _ in
                MainActor.assumeIsolated { AppDependencies.current?.stopTrip() }
            }]
        case .none:
            return []
        }
    }
}
