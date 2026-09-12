import Foundation

/// The span a report covers.
///
/// A trip belongs to the period that contains the moment it **started**. A drive that
/// crosses midnight, a quarter end or New Year is therefore counted once, in the period it
/// began in — the alternative, splitting it, would invent kilometres that no odometer ever
/// showed.
enum ReportPeriod: Hashable, Sendable {
    case month(year: Int, month: Int)
    case quarter(year: Int, quarter: Int)
    case year(Int)
    case custom(start: Date, end: Date)

    static func current(calendar: Calendar = .current, now: Date = .now) -> ReportPeriod {
        let components = calendar.dateComponents([.year, .month], from: now)
        return .month(year: components.year ?? 2026, month: components.month ?? 1)
    }

    /// Half-open in practice: `contains` uses `start <= date < end`, so the last instant of
    /// a month cannot land in two periods at once.
    func range(calendar: Calendar = .current) -> Range<Date> {
        switch self {
        case let .month(year, month):
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return start..<end

        case let .quarter(year, quarter):
            let firstMonth = (max(1, min(4, quarter)) - 1) * 3 + 1
            let start = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1)) ?? .distantPast
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start
            return start..<end

        case let .year(year):
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
            return start..<end

        case let .custom(start, end):
            let dayStart = calendar.startOfDay(for: start)
            let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            return dayStart..<max(dayAfterEnd, dayStart)
        }
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        range(calendar: calendar).contains(date)
    }

    /// The tax year a trip counts towards, used to accumulate distance for tiered scales.
    /// Calendar year: the countries whose tax year is offset (the UK's 6 April) are handled
    /// by their pack's validity window, not by shifting every user's reports.
    static func taxYear(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date)
    }

    func title(locale: Locale, calendar: Calendar = .current) -> String {
        var formatterCalendar = calendar
        formatterCalendar.locale = locale
        let start = range(calendar: calendar).lowerBound

        switch self {
        case .month:
            return start.formatted(.dateTime.month(.wide).year().locale(locale))
        case let .quarter(year, quarter):
            return "Q\(quarter) \(year.formatted(.number.grouping(.never).locale(locale)))"
        case let .year(year):
            return year.formatted(.number.grouping(.never).locale(locale))
        case let .custom(from, to):
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale)
            return "\(from.formatted(style)) – \(to.formatted(style))"
        }
    }
}
