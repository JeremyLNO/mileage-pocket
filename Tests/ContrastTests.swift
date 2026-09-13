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

    /// `AccentColor` tints everything nothing else claims — toolbar buttons, links, the
    /// controls on a sheet presented outside the tab bar's own tint. It lived in the asset
    /// catalogue at the *original* bright amber while `Theme.signal` was darkened, so the
    /// paywall's own Close and Restore stayed at 2.7:1 while the rest of the app moved.
    func testTheAccentColourMatchesTheBrandColourItIsSupposedToBe() throws {
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"), "AccentColor must exist")
        let signal = UIColor(Theme.signal)

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            var accentComponents = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            var signalComponents = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            accent.resolvedColor(with: traits)
                .getRed(&accentComponents.0, green: &accentComponents.1, blue: &accentComponents.2, alpha: &accentComponents.3)
            signal.resolvedColor(with: traits)
                .getRed(&signalComponents.0, green: &signalComponents.1, blue: &signalComponents.2, alpha: &signalComponents.3)

            let label = style == .light ? "light" : "dark"
            XCTAssertEqual(accentComponents.0, signalComponents.0, accuracy: 0.01, "red in \(label)")
            XCTAssertEqual(accentComponents.1, signalComponents.1, accuracy: 0.01, "green in \(label)")
            XCTAssertEqual(accentComponents.2, signalComponents.2, accuracy: 0.01, "blue in \(label)")
        }
    }

    /// The dial is a gradient, so the label has to hold against **both** ends of it — and the
    /// light end is where it fails. "START" in white measured 1.84:1 there: the largest, most
    /// important control in the app carrying its least readable text, which a flat-colour
    /// test could not see because the dial has no flat colour.
    func testTheDialsLabelHoldsAgainstBothEndsOfTheGradient() {
        assertReadable(Theme.onDial, on: Theme.dialHoney, "START on the light end of the dial")
        assertReadable(Theme.onDial, on: Theme.dialAmber, "START on the dark end of the dial")
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
