import SwiftUI

/// Two roles, deliberately paired.
///
/// Text is the system face — it is what an iPhone owner reads everywhere else, and nothing
/// about a mileage log is served by a display serif. Numbers are monospaced and tabular:
/// the distance readout ticks up while the phone sits in a cradle, and proportional digits
/// make it jump sideways on every change. That stability is the type decision here.
extension Font {
    /// The oversized figure on Home and in trip mode.
    static func meter(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static var meterLarge: Font { .meter(64, weight: .medium) }
    static var meterMedium: Font { .meter(34, weight: .medium) }
    static var meterSmall: Font { .meter(17, weight: .medium) }

    /// The small uppercase label that sits beside a figure ("KM", "BUSINESS").
    static var eyebrow: Font { .system(size: 12, weight: .semibold, design: .rounded) }
}

extension View {
    /// Applies the tracking used on eyebrow labels; kept here so the value is set once.
    func eyebrowStyle(_ color: Color = Theme.textSecondary) -> some View {
        self.font(.eyebrow)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
