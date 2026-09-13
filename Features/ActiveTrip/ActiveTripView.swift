import CoreLocation
import MapKit
import SwiftUI

/// The one screen used at the wheel.
///
/// It commits to a dark ground whatever the system appearance: a phone in a cradle is read
/// at a glance, often at night, and a white full-screen panel is a headlight in the cabin.
/// Three things are shown — clock, distance, stop — and nothing else competes with them.
struct ActiveTripView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @State private var camera: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    )
    @State private var now = Date.now

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var settings: UserSettings { dependencies.settingsStore.settings }
    private var unit: DistanceUnit { settings.distanceUnit }

    var body: some View {
        @Bindable var dependencies = dependencies

        return ZStack {
            map
            VStack(spacing: 0) {
                readout
                Spacer()
                stopButton
            }
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onReceive(tick) { now = $0 }
        .onChange(of: dependencies.activeRoute.count) { _, _ in
            guard let last = dependencies.activeRoute.last else { return }
            camera = .region(MKCoordinateRegion(
                center: last,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        }
        .statusBarHidden(false)
        .alert(
            L.string("activetrip.stop.failed.title"),
            isPresented: $dependencies.stopFailed
        ) {
            Button(L.string("common.ok"), role: .cancel) {}
        } message: {
            Text(L.string("activetrip.stop.failed.message"))
        }
    }

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
            if dependencies.activeRoute.count > 1 {
                MapPolyline(coordinates: dependencies.activeRoute)
                    .stroke(Theme.signal, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .overlay {
            LinearGradient(
                colors: [Theme.ink.opacity(0.95), Theme.ink.opacity(0.25), Theme.ink.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var readout: some View {
        VStack(spacing: 10) {
            Text("activetrip.recording")
                .eyebrowStyle(Theme.signal)

            Text(Fmt.timer(dependencies.activeDuration(now: now)))
                .scaledFont(40, relativeTo: .largeTitle, weight: .medium, design: .monospaced, maximum: 60)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))

            MeterReadout(
                value: Fmt.distanceValue(meters: dependencies.activeDistanceMeters, unit: unit, locale: locale),
                unit: Fmt.unitAbbreviation(unit, locale: locale),
                size: 76,
                color: .white
            )

            if let vehicle = dependencies.activeVehicleName {
                Label(vehicle, systemImage: "car.side.fill")
                    .scaledFont(14, relativeTo: .subheadline, weight: .medium)
                    .foregroundStyle(.white.opacity(0.55))
            }

            if dependencies.isTripPaused {
                Label("activetrip.paused", systemImage: "pause.circle.fill")
                    .scaledFont(13, relativeTo: .footnote, weight: .semibold)
                    .foregroundStyle(Theme.signal)
            }
        }
        .padding(.top, 28)
        .accessibilityElement(children: .combine)
    }

    private var stopButton: some View {
        Button {
            dependencies.stopTrip()
        } label: {
            Text("activetrip.stop")
                .scaledFont(26, relativeTo: .title2, weight: .bold, design: .rounded)
                .tracking(2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(Theme.stop.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .accessibilityLabel(Text("activetrip.stop.accessibility"))
    }
}
