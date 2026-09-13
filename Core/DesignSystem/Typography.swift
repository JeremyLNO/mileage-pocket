import SwiftUI

/// Two roles, deliberately paired.
///
/// Text is the system face — it is what an iPhone owner reads everywhere else, and nothing
/// about a mileage log is served by a display serif. Numbers are monospaced and tabular:
/// the distance readout ticks up while the phone sits in a cradle, and proportional digits
/// make it jump sideways on every change. That stability is the type decision here.
/// The sizes the meter is set at. They are plain numbers rather than `Font` values because a
/// `Font` built from `system(size:)` cannot scale: the size has to reach `@ScaledMetric`
/// before it becomes a font. See `scaledFont(_:relativeTo:weight:design:maximum:)`.
enum MeterSize {
    /// The oversized figure on Home and in trip mode.
    static let large: CGFloat = 64
    static let medium: CGFloat = 34
    static let small: CGFloat = 17
    /// The small uppercase label that sits beside a figure ("KM", "BUSINESS").
    static let eyebrow: CGFloat = 12
}

extension View {
    /// Applies the tracking used on eyebrow labels; kept here so the value is set once.
    func eyebrowStyle(_ color: Color = Theme.textSecondary) -> some View {
        self.scaledFont(12, relativeTo: .caption, weight: .semibold, design: .rounded)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Fixed point sizes that follow the reader's text size.
///
/// `Font.system(size:)` is frozen: it renders 13 pt whether the phone is set to the smallest
/// text or to the largest accessibility size. The app was built entirely from fixed sizes,
/// so Dynamic Type — the single most used accessibility setting on iOS — did nothing at all
/// here, and the one screen used at the wheel was the one that needed it most.
///
/// `@ScaledMetric` restores the scaling while keeping the composition the design depends on:
/// at the default text size the number is unchanged, so nothing moves for a reader who never
/// touches the setting.
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maximum: CGFloat

    init(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        weight: Font.Weight,
        design: Font.Design,
        maximum: CGFloat
    ) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
        self.maximum = maximum
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(scaledSize, maximum), weight: weight, design: design))
    }
}

extension View {
    /// A system font at `size` that grows with the reader's text size.
    ///
    /// - Parameters:
    ///   - textStyle: which of iOS's ramps the size rides. Picked to match the role the size
    ///     plays — a 12 pt label tracks `.caption`, a 26 pt title tracks `.title`.
    ///   - maximum: a ceiling, for the few figures whose container cannot grow without the
    ///     layout collapsing — the driving readout, chiefly. Unbounded by default.
    func scaledFont(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        maximum: CGFloat = .greatestFiniteMagnitude
    ) -> some View {
        modifier(ScaledFontModifier(
            size: size, relativeTo: textStyle, weight: weight, design: design, maximum: maximum
        ))
    }
}
