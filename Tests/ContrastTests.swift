import SwiftUI
import XCTest
@testable import MileagePocket

/// Every colour the app draws *text* in has to be legible on the surface behind it.
///
/// WCAG 2.1 asks 4.5:1 for body text. The brand amber measured 3.05:1 on white and was used
/// for the eyebrow labels, the tint on every button and the tab bar — the smallest text in
/// the app, in the colour hardest to read. It is the kind of fault no screenshot review
/// catches, because it looks fine to whoever chose it.
final class ContrastTests: XCTestCase {
    private func luminance(_ color: UIColor, _ style: UIUserInterfaceStyle) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func ratio(_ a: Color, on b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let first = luminance(UIColor(a), style)
        let second = luminance(UIColor(b), style)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func assertReadable(
        _ foreground: Color,
        on background: Color,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let measured = ratio(foreground, on: background, style)
            XCTAssertGreaterThanOrEqual(
                measured, 4.5,
                "\(name) in \(style == .light ? "light" : "dark") measures \(String(format: "%.2f", measured)):1",
                file: file, line: line
            )
        }
    }

    func testEveryTextColourIsReadableOnItsSurface() {
        assertReadable(Theme.signal, on: Theme.surface, "signal on a card")
        assertReadable(Theme.signal, on: Theme.background, "signal on the page")
        assertReadable(Theme.business, on: Theme.surface, "business on a card")
        assertReadable(Theme.personal, on: Theme.surface, "personal on a card")
        assertReadable(Theme.textPrimary, on: Theme.surface, "primary text")
        assertReadable(Theme.textSecondary, on: Theme.surface, "secondary text")
        assertReadable(Theme.textSecondary, on: Theme.background, "secondary text on the page")
    }

    /// The START and STOP buttons put a label on a filled colour; the label *is* the control.
    func testLabelsOnFilledControlsAreReadable() {
        assertReadable(Theme.onSignal, on: Theme.signal, "the primary button's label")
        assertReadable(.white, on: Theme.stop, "the stop button's label")
    }

    /// Trip mode pins itself to dark whatever the system appearance, so it is measured there
    /// and only there — asserting light would be asserting a screen that never renders.
    func testTheDrivingScreenIsReadable() {
        for (name, colour) in [("the driving readout", Color.white), ("the recording label", Theme.signal)] {
            let measured = ratio(colour, on: Theme.ink, .dark)
            XCTAssertGreaterThanOrEqual(
                measured, 4.5,
                "\(name) measures \(String(format: "%.2f", measured)):1 on the trip-mode ground"
            )
        }
    }
}
