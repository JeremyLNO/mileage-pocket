import SwiftUI

// MARK: - Cards

/// The app's one container. Everything that groups content uses it, so spacing and corner
/// radius never drift between screens.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 0.5)
            )
    }
}

// MARK: - Numbers

/// A figure and its unit, set as a trip meter: the number in tabular monospaced digits so
/// its width never changes, the unit small and quiet beside it.
struct MeterReadout: View {
    let value: String
    let unit: String
    var size: CGFloat = 64
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                // Capped: this figure sits in a fixed cradle-height layout, and the ramp at
                // the largest accessibility sizes would take a 64 pt number past the width of
                // the phone. It still grows — just not without limit.
                .scaledFont(
                    size, relativeTo: .largeTitle, weight: .medium,
                    design: .monospaced, maximum: size * 1.5
                )
                .monospacedDigit()
                .tracking(-1)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(unit)
                .scaledFont(max(13, size * 0.26), relativeTo: .footnote, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - Controls

/// The primary action, used for START, STOP and the paywall CTA — nothing else.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var tint: Color = Theme.signal
    /// What the label is drawn in. Follows the fill rather than being white by default: the
    /// dark-mode amber under a white label measured 2.1:1.
    var labelColor: Color = Theme.onSignal
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .scaledFont(17, relativeTo: .body, weight: .semibold)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(labelColor)
            .background(tint.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(16, relativeTo: .body, weight: .medium)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 0.5)
                )
        }
    }
}

/// The signature control: a dial, not a pill. A tick ring marks the face; while a trip runs
/// the ring fills with the distance covered, so the button itself is the instrument.
struct DialButton: View {
    let title: LocalizedStringKey
    var subtitle: String?
    var progress: Double?
    var tint: Color = Theme.signal
    var diameter: CGFloat = 220
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 10)
                    .frame(width: diameter + 22, height: diameter + 22)

                if let progress {
                    Circle()
                        .trim(from: 0, to: max(0.002, min(1, progress)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: diameter + 22, height: diameter + 22)
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress)
                }

                Circle()
                    .fill(Theme.dialGradient)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: tint.opacity(0.35), radius: 22, y: 10)

                VStack(spacing: 4) {
                    Text(title)
                        .scaledFont(26, relativeTo: .title2, weight: .bold, design: .rounded)
                        .tracking(1.5)
                    if let subtitle {
                        Text(subtitle)
                            .scaledFont(13, relativeTo: .footnote, weight: .medium)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(Theme.onDial)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

/// Business / Personal marker. Colour alone never carries the meaning — the label is always
/// present, which also makes the list readable to VoiceOver without extra work.
struct TripTypePill: View {
    let type: TripType

    var body: some View {
        Text(type == .business ? "trip.type.business" : "trip.type.personal")
            .eyebrowStyle(Theme.tint(for: type))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.tint(for: type).opacity(0.12), in: Capsule())
    }
}

/// A labelled figure in a row of three on Home and Reports.
struct StatTile: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Shrinks rather than wraps: one tile wrapping to two lines pushes its value out
            // of alignment with the tiles beside it.
            Text(label)
                .eyebrowStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .scaledFont(17, relativeTo: .body, weight: .medium, design: .monospaced)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown when a list has nothing in it yet. An empty screen is an invitation to act, so it
/// says what to do next rather than stating that there is nothing.
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .scaledFont(40, relativeTo: .largeTitle, weight: .light)
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .scaledFont(18, relativeTo: .title3, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .scaledFont(15, relativeTo: .subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}
