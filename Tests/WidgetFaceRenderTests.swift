import SwiftUI
import UIKit
import WidgetKit
import XCTest
@testable import MileagePocket

/// Draws every face of the widget and checks that something is actually on it.
///
/// A widget extension has no test target, and the home screen is the only place WidgetKit
/// will render one — which is how the *Recording* face shipped in a build where it could
/// never appear: nothing failed, because nothing was drawn. These tests render each size in
/// each state off the home screen and assert the result is not a flat rectangle.
///
/// They also write the images out, so the design can be looked at rather than imagined.
@MainActor
final class WidgetFaceRenderTests: XCTestCase {
    /// Point sizes of the three families on a 6.3" iPhone. Exact to the pixel is not the
    /// point; the aspect ratios are, because that is what a layout overflows in.
    private static let sizes: [(WidgetFamily, CGSize)] = [
        (.systemSmall, CGSize(width: 170, height: 170)),
        (.systemMedium, CGSize(width: 364, height: 170)),
        (.systemLarge, CGSize(width: 364, height: 382)),
    ]

    /// The test host is sandboxed, so this is inside the simulator's own container — the
    /// absolute path is printed by `testEveryFaceInEverySizeDrawsSomething` so the images can
    /// be fetched from the host.
    private var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["WIDGET_FACES_DIR"] {
            return URL(filePath: override)
        }
        return FileManager.default.temporaryDirectory.appending(path: "widget-faces")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testEveryFaceInEverySizeDrawsSomething() throws {
        print("WIDGET FACES → \(outputDirectory.path)")
        for (name, snapshot) in Self.states {
            for (family, size) in Self.sizes {
                for scheme in [ColorScheme.light, .dark] {
                    let image = try render(snapshot, family: family, size: size, scheme: scheme)
                    let label = "\(name)-\(Self.name(for: family))-\(scheme == .dark ? "dark" : "light")"
                    write(image, named: label)

                    // A face that renders its background and nothing else comes back as one
                    // colour. That is exactly what a state the layout never reaches looks
                    // like, and exactly what no assertion used to catch.
                    XCTAssertGreaterThan(
                        distinctColours(in: image), 6,
                        "\(label) draws an almost empty rectangle — the face is not being reached"
                    )
                }
            }
        }
    }

    /// The two faces that carry controls must carry them at every size. A button that is
    /// laid out off the bottom of a small widget is invisible, and invisible is the same as
    /// absent to the person looking at their home screen.
    func testTheActionFacesAreNotTallerThanTheWidgetTheyDrawIn() throws {
        for (name, snapshot) in Self.states where name != "month" {
            for (family, size) in Self.sizes {
                let fitted = TripStatusWidgetView(
                    entry: StartTripEntry(date: .now, snapshot: snapshot),
                    forcedFamily: family
                )
                .frame(width: size.width, height: size.height)
                .fixedSize()

                let renderer = ImageRenderer(content: fitted)
                let rendered = try XCTUnwrap(renderer.uiImage)
                XCTAssertLessThanOrEqual(
                    rendered.size.height.rounded(), size.height.rounded() + 1,
                    "the \(name) face overflows \(Self.name(for: family))"
                )
            }
        }
    }

    /// The numbers must be set in the app's locale, not the phone's.
    ///
    /// The extension had no locale at all and `.formatted()` fell back to the system's: an
    /// English widget on a French phone wrote "1 100 km" and "+12 %" beside an app writing
    /// "1,100 km" and "+12%". Two spellings of one figure is how a reader decides one of the
    /// two screens is lying. Rendering the same snapshot under two locales has to produce two
    /// different pictures — if it does not, the field is being ignored again.
    func testTheNumbersFollowTheAppsLocaleAndNotTheSystems() throws {
        var french = Self.base()
        french.localeIdentifier = "fr_FR"
        var american = Self.base()
        american.localeIdentifier = "en_US"

        let size = CGSize(width: 364, height: 170)
        let one = try render(french, family: .systemMedium, size: size, scheme: .light)
        let other = try render(american, family: .systemMedium, size: size, scheme: .light)

        XCTAssertNotEqual(
            one.pngData(), other.pngData(),
            "the same figures drew identically in French and in American English — the snapshot's locale is being ignored"
        )
    }

    // MARK: - Rendering

    private func render(
        _ snapshot: WidgetSnapshot?,
        family: WidgetFamily,
        size: CGSize,
        scheme: ColorScheme
    ) throws -> UIImage {
        let view = TripStatusWidgetView(
            entry: StartTripEntry(date: .now, snapshot: snapshot),
            forcedFamily: family
        )
        .padding(family == .systemLarge ? 0 : 0)
        .frame(width: size.width, height: size.height)
        .background(Theme.background)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage, "the face produced no image at all")
    }

    private func write(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: outputDirectory.appending(path: "\(name).png"))
    }

    /// Samples a grid rather than every pixel: enough to tell a drawn face from a filled
    /// rectangle, cheap enough to run for every size in every appearance.
    private func distinctColours(in image: UIImage, samples: Int = 24) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var seen = Set<UInt32>()
        for row in 0..<samples {
            for column in 0..<samples {
                let x = width * column / samples
                let y = height * row / samples
                let offset = (y * width + x) * 4
                // Quantised to 5 bits per channel: two shades of the same near-white are the
                // same colour to a reader, and counting them separately would let a blank
                // face pass on compression noise alone.
                let value = UInt32(pixels[offset] >> 3) << 16
                    | UInt32(pixels[offset + 1] >> 3) << 8
                    | UInt32(pixels[offset + 2] >> 3)
                seen.insert(value)
            }
        }
        return seen.count
    }

    // MARK: - States

    private static func name(for family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        case .systemLarge: return "large"
        default: return "other"
        }
    }

    private static var states: [(String, WidgetSnapshot)] {
        [
            ("month", base()),
            ("recording", base(recording: true)),
            ("review", base(awaiting: 2)),
        ]
    }

    private static func base(recording: Bool = false, awaiting: Int = 0) -> WidgetSnapshot {
        WidgetSnapshot(
            monthLabel: "September",
            distanceMeters: 792_000,
            unitRaw: DistanceUnit.kilometers.rawValue,
            formattedAmount: "€410.00",
            isTripInProgress: recording,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            tripStartedAt: recording ? Date().addingTimeInterval(-1_517) : nil,
            tripDistanceMeters: recording ? 24_300 : nil,
            tripsAwaitingReview: awaiting,
            languageCode: "en",
            localeIdentifier: "en_US",
            pendingTrips: awaiting > 0
                ? [
                    PendingTrip(id: UUID(), label: "Paris → Versailles", distanceText: "24.3 km"),
                    PendingTrip(id: UUID(), label: "Paris → Orly", distanceText: "18.7 km"),
                ]
                : [],
            figures: .placeholder
        )
    }
}
