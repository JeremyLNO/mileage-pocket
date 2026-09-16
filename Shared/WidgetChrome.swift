import SwiftUI

/// The pieces every face of the widget is built from.
///
/// They exist so the three sizes are the same design at three scales rather than three
/// drawings that resemble each other: one tile, one icon chip, one way to set a figure. The
/// palette is the app's own (`Theme`, now in `Shared/`) — a home screen in colours the app
/// does not use reads as a different product from the one it opens.
enum WidgetChrome {
    static let tileRadius: CGFloat = 16
    static let tileSpacing: CGFloat = 8
}

// MARK: - Tile

/// One white card on the widget's ground. The large face is a grid of these; the small face
/// is one of them, full-bleed.
struct WidgetTile<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            // Vertically centred, not pinned to the top. A grid of tiles never divides into
            // exactly the height its contents want, and top-aligned content turned every
            // spare point into a band of empty white under the figure.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                Theme.surface,
                in: RoundedRectangle(cornerRadius: WidgetChrome.tileRadius, style: .continuous)
            )
    }
}

// MARK: - Labels

/// The tinted disc and its label, the mark at the top of every tile.
struct WidgetTileHeader: View {
    let systemImage: String
    let title: String
    var tint: Color = Theme.signal
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// A figure and its unit, set the way the app sets one: the number heavy and tabular, the
/// unit small and quiet beside it, so a changing digit never shifts the layout.
struct WidgetFigure: View {
    let value: String
    var unit: String?
    var size: CGFloat = 26
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            if let unit {
                Text(unit)
                    .font(.system(size: max(11, size * 0.42), weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// "▲ +12% vs yesterday". Drawn only when there is a yesterday to compare against — the
/// caller decides, because a day off is not a hundred per cent of anything.
struct WidgetTrend: View {
    let change: Double
    let label: String
    let locale: Locale

    private var isUp: Bool { change >= 0 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(change.formatted(
                .percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(locale)
            ))
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(isUp ? Theme.business : Theme.personal)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - The split

/// The month in one bar: work on the left, private life on the right.
///
/// The two colours are the app's own `business` and `personal`, the same pair used on every
/// trip row and every report — so the bar needs no key beyond the one under it.
struct WidgetSplitBar: View {
    /// 0...1.
    let businessShare: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let business = max(0, min(1, businessShare))
            HStack(spacing: 0) {
                Rectangle().fill(Theme.business).frame(width: width * business)
                Rectangle().fill(Theme.personal)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

struct WidgetSplitLegend: View {
    let businessShare: Double
    let businessLabel: String
    let personalLabel: String
    let locale: Locale

    var body: some View {
        HStack(spacing: 10) {
            entry(share: businessShare, label: businessLabel, tint: Theme.business)
            entry(share: 1 - businessShare, label: personalLabel, tint: Theme.personal)
        }
    }

    private func entry(share: Double, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(share.formatted(.percent.precision(.fractionLength(0)).locale(locale)))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: - The road

/// The band at the foot of the widget when there is nothing to do.
///
/// Drawn rather than shipped as an image: a picture would need a light and a dark copy at
/// three scales, and a widget that renders in the wrong appearance is a widget nobody can
/// read. Shapes follow the palette for free.
///
/// It appears only on the idle faces. While a drive is running, or while a trip is waiting
/// to be classified, that space belongs to the control — decoration does not outrank the one
/// thing the app is asking for.
struct RoadIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [Theme.personal.opacity(0.20), Theme.personal.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Three bands, back to front, each lower and greener than the one behind it.
                // Depth here is entirely overlap and value — no perspective maths, and none
                // needed at 80 points tall.
                hill(crest: 0.62, base: 0.46, sag: 0.10, tint: Theme.business.opacity(0.18), w: w, h: h)
                hill(crest: 0.26, base: 0.66, sag: 0.14, tint: Theme.business.opacity(0.30), w: w, h: h)
                road(w: w, h: h)
                hill(crest: 0.80, base: 0.94, sag: 0.10, tint: Theme.business.opacity(0.46), w: w, h: h)
                car(w: w, h: h)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.tileRadius, style: .continuous))
    }

    /// A rolling band: a crest at `crest` (0…1 across), its top at `base` (0…1 down), and a
    /// `sag` that dips the sides so the shape reads as a hill rather than a wave.
    private func hill(crest: Double, base: Double, sag: Double, tint: Color, w: CGFloat, h: CGFloat) -> some View {
        Path { path in
            let top = h * base
            path.move(to: CGPoint(x: -w * 0.05, y: top + h * sag))
            path.addCurve(
                to: CGPoint(x: w * 1.05, y: top + h * sag),
                control1: CGPoint(x: w * crest - w * 0.30, y: top - h * sag),
                control2: CGPoint(x: w * crest + w * 0.30, y: top - h * sag)
            )
            path.addLine(to: CGPoint(x: w * 1.05, y: h * 1.05))
            path.addLine(to: CGPoint(x: -w * 0.05, y: h * 1.05))
            path.closeSubpath()
        }
        .fill(tint)
    }

    /// Wide at the reader's feet, a few points across at the horizon. Two edges converging on
    /// a point is the whole illusion.
    private func road(w: CGFloat, h: CGFloat) -> some View {
        let horizonX = w * 0.70
        let horizonY = h * 0.52
        return Path { path in
            path.move(to: CGPoint(x: w * 0.04, y: h * 1.05))
            path.addQuadCurve(
                to: CGPoint(x: horizonX - w * 0.015, y: horizonY),
                control: CGPoint(x: w * 0.44, y: h * 0.86)
            )
            path.addLine(to: CGPoint(x: horizonX + w * 0.015, y: horizonY))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.56, y: h * 1.05),
                control: CGPoint(x: w * 0.62, y: h * 0.88)
            )
            path.closeSubpath()
        }
        .fill(Self.roadTint.opacity(0.92))
    }

    /// The road and the car are near-white in *both* appearances, not `Theme.surface`.
    ///
    /// Surface follows the interface style, so in dark mode the road came out darker than
    /// the hills around it: the ribbon read as a crack in the ground and the car as a hole
    /// in the ribbon. A road is lighter than the grass at every hour of the day.
    static let roadTint = Color(light: 0xFFFFFF, dark: 0xDCE6F0)

    private func car(w: CGFloat, h: CGFloat) -> some View {
        Image(systemName: "car.side.fill")
            .font(.system(size: min(20, h * 0.30), weight: .medium))
            .foregroundStyle(Self.roadTint)
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            // On the near stretch of road, where the ribbon is widest — a car drawn up by
            // the horizon would be the size of the hill behind it. Kept clear of the bottom
            // edge: the band is 60 points tall on the small face, and at 0.86 down the car
            // was sitting half outside its own picture.
            .position(x: w * 0.30, y: h * 0.78)
    }
}
