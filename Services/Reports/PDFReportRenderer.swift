import Foundation
import PDFKit
import UIKit

/// Renders the mileage report.
///
/// This document is the product's end point: it is what gets emailed to an employer or
/// handed to an accountant, so it is built to be read by someone who has never heard of the
/// app — every figure is traceable to the rule that produced it, and the footer names that
/// rule, its version and its source.
struct PDFReportRenderer {
    // A4 at 72 dpi.
    private let pageSize = CGSize(width: 595.2, height: 841.8)
    private let margin: CGFloat = 44
    private let rowHeight: CGFloat = 22
    private let headerRowHeight: CGFloat = 26

    enum RenderError: Error {
        case couldNotWriteFile
    }

    func render(_ data: ReportData, profile: ReportProfile, to url: URL) throws -> URL {
        // The document is written in the language the user picked, not the device's: a
        // French driver hands this to a French accountant, and it used to come out in
        // English whatever the app was set to.
        let t = LocalizedStrings(locale: profile.locale)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(t("pdf.document.title")) — \(data.period.title(locale: profile.locale))",
            kCGPDFContextAuthor as String: profile.userName,
            kCGPDFContextCreator as String: "Mileage Pocket",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        let pages = paginate(data)
        let pageCount = max(1, pages.count)

        let pdf = renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                var y = margin

                if index == 0 {
                    y = drawDocumentHeader(data, profile: profile, at: y)
                    y += 12
                    y = drawSummary(data, profile: profile, at: y)
                    y += 16
                }

                y = drawTableHeader(profile: profile, at: y)
                for row in page {
                    y = drawRow(row, profile: profile, at: y, alternate: shouldShade(row, in: data))
                }

                if index == pages.count - 1 {
                    y += 4
                    y = drawTotals(data, profile: profile, at: y)
                    y += 18
                    drawDisclaimer(profile: profile, data: data, at: y)
                }

                drawPageFooter(profile: profile, page: index + 1, of: pageCount)
            }

            // A report with no trips still produces a document: an empty month is itself a
            // statement, and a missing file would look like a failure.
            if pages.isEmpty {
                context.beginPage()
                var y = margin
                y = drawDocumentHeader(data, profile: profile, at: y)
                y += 12
                y = drawSummary(data, profile: profile, at: y)
                y += 20
                draw(t("pdf.empty"), at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 11), color: .secondaryLabel)
                drawPageFooter(profile: profile, page: 1, of: 1)
            }
        }

        do {
            try pdf.write(to: url, options: .atomic)
        } catch {
            throw RenderError.couldNotWriteFile
        }
        return url
    }

    // MARK: - Layout

    private var columns: [CGFloat] { [62, 92, 92, 86, 66, 52, 57] }

    private func columnX(_ index: Int) -> CGFloat {
        margin + columns.prefix(index).reduce(0, +)
    }

    private var contentWidth: CGFloat { columns.reduce(0, +) }

    /// Splits rows into pages. The first page carries the header block, so it fits fewer
    /// rows than the ones after it — computing that instead of assuming a fixed count is
    /// what keeps the last page from overflowing silently.
    private func paginate(_ data: ReportData) -> [[ReportRow]] {
        guard !data.rows.isEmpty else { return [] }
        // The closing block — totals plus up to five wrapped disclaimer lines — has to fit
        // under the last page's rows. Reserving for it here is what keeps it from being
        // pushed off the page, where it would vanish without any error.
        let closingBlockHeight: CGFloat = 130
        let firstPageCapacity = Int((pageSize.height - margin * 2 - 210 - headerRowHeight - closingBlockHeight) / rowHeight)
        let otherPageCapacity = Int((pageSize.height - margin * 2 - headerRowHeight - closingBlockHeight) / rowHeight)

        var pages: [[ReportRow]] = []
        var remaining = data.rows[...]

        let first = remaining.prefix(max(1, firstPageCapacity))
        pages.append(Array(first))
        remaining = remaining.dropFirst(first.count)

        while !remaining.isEmpty {
            let slice = remaining.prefix(max(1, otherPageCapacity))
            pages.append(Array(slice))
            remaining = remaining.dropFirst(slice.count)
        }
        return pages
    }

    private func shouldShade(_ row: ReportRow, in data: ReportData) -> Bool {
        guard let index = data.rows.firstIndex(where: { $0.id == row.id }) else { return false }
        return index.isMultiple(of: 2)
    }

    // MARK: - Blocks

    private func drawDocumentHeader(_ data: ReportData, profile: ReportProfile, at y: CGFloat) -> CGFloat {
        let t = LocalizedStrings(locale: profile.locale)
        var cursor = y
        draw(t("pdf.title"), at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 10, weight: .semibold), color: .systemOrange)
        cursor += 16
        draw(data.period.title(locale: profile.locale), at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 26, weight: .bold))
        cursor += 34

        let left: [(String, String)] = [
            (t("pdf.name"), profile.userName),
            (t("pdf.company"), profile.companyName ?? "—"),
            (t("pdf.vehicle"), profile.vehicleLabel ?? "—"),
        ]
        let right: [(String, String)] = [
            (t("pdf.country"), profile.countryName),
            (t("pdf.rule"), profile.ruleDescription),
            (t("pdf.rule.version"), profile.ruleVersion),
        ]

        let columnStart = cursor
        for (label, value) in left {
            drawLabelledValue(label, value, at: CGPoint(x: margin, y: cursor), width: contentWidth / 2 - 12)
            cursor += 28
        }

        var rightCursor = columnStart
        for (label, value) in right {
            // The rule's own name is long and is the one field a reader checks: it wraps
            // rather than ending in an ellipsis.
            let wraps = label == t("pdf.rule")
            let used = drawLabelledValue(
                label, value,
                at: CGPoint(x: margin + contentWidth / 2, y: rightCursor),
                width: contentWidth / 2,
                wraps: wraps
            )
            rightCursor += max(28, used)
        }

        let bottom = max(cursor, rightCursor)
        drawRule(y: bottom + 2)
        return bottom + 8
    }

    private func drawSummary(_ data: ReportData, profile: ReportProfile, at y: CGFloat) -> CGFloat {
        let t = LocalizedStrings(locale: profile.locale)
        // Every currency present, not a sum of dollars and euros under one symbol.
        let totals = data.totalsByCurrency
            .map { Fmt.money($0.amount, currencyCode: $0.currency, locale: profile.locale) }
            .joined(separator: " + ")
        let tiles: [(String, String)] = [
            (t("pdf.summary.trips"), "\(data.businessTripCount)"),
            (t("pdf.summary.distance"), Fmt.distance(meters: data.totalDistanceMeters, unit: profile.unit, locale: profile.locale)),
            (profile.isOfficialRate ? t("pdf.summary.deduction") : t("pdf.summary.reimbursement"),
             totals.isEmpty ? "—" : totals),
        ]
        let tileWidth = contentWidth / CGFloat(tiles.count)
        for (index, tile) in tiles.enumerated() {
            let x = margin + CGFloat(index) * tileWidth
            draw(tile.0.uppercased(), at: CGPoint(x: x, y: y), font: .systemFont(ofSize: 8, weight: .semibold), color: .secondaryLabel)
            draw(tile.1, at: CGPoint(x: x, y: y + 12), font: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold))
        }
        return y + 38
    }

    private func drawTableHeader(profile: ReportProfile, at y: CGFloat) -> CGFloat {
        let t = LocalizedStrings(locale: profile.locale)
        let unit = profile.unit == .kilometers ? "km" : "mi"
        let titles = [
            t("pdf.column.date"), t("pdf.column.from"), t("pdf.column.to"), t("pdf.column.purpose"),
            t.format("pdf.column.distance", unit), t("pdf.column.rate"), t("pdf.column.amount"),
        ]
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: headerRowHeight)
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()

        for (index, title) in titles.enumerated() {
            let alignment: NSTextAlignment = index >= 4 ? .right : .left
            draw(
                title,
                in: CGRect(x: columnX(index) + 5, y: y + 8, width: columns[index] - 10, height: 14),
                font: .systemFont(ofSize: 7.5, weight: .semibold),
                color: .secondaryLabel,
                alignment: alignment
            )
        }
        return y + headerRowHeight
    }

    private func drawRow(_ row: ReportRow, profile: ReportProfile, at y: CGFloat, alternate: Bool) -> CGFloat {
        if alternate {
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)).fill()
        }

        let dateStyle = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year().locale(profile.locale)
        let purpose = row.isManuallyEdited ? "\(row.purpose) (edited)" : row.purpose
        let values = [
            row.date.formatted(dateStyle),
            row.from,
            row.to,
            purpose,
            Fmt.distanceValue(meters: row.distanceMeters, unit: profile.unit, locale: profile.locale),
            row.rate.map { Fmt.rateAmount($0, currencyCode: row.currencyCode ?? "EUR", locale: profile.locale) } ?? "—",
            row.amount.map { Fmt.money($0, currencyCode: row.currencyCode ?? "EUR", locale: profile.locale) } ?? "—",
        ]

        for (index, value) in values.enumerated() {
            let numeric = index >= 4
            draw(
                value,
                in: CGRect(x: columnX(index) + 5, y: y + 6, width: columns[index] - 10, height: 14),
                font: numeric ? .monospacedDigitSystemFont(ofSize: 8, weight: .regular) : .systemFont(ofSize: 8),
                color: .label,
                alignment: numeric ? .right : .left
            )
        }
        return y + rowHeight
    }

    private func drawTotals(_ data: ReportData, profile: ReportProfile, at y: CGFloat) -> CGFloat {
        let t = LocalizedStrings(locale: profile.locale)
        drawRule(y: y)
        let cursor = y + 6
        draw(t.format("pdf.totals", data.businessTripCount), at: CGPoint(x: margin + 5, y: cursor + 4), font: .systemFont(ofSize: 9, weight: .semibold))
        draw(
            Fmt.distanceValue(meters: data.totalDistanceMeters, unit: profile.unit, locale: profile.locale),
            in: CGRect(x: columnX(4) + 5, y: cursor + 4, width: columns[4] - 10, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            alignment: .right
        )
        let totals = data.totalsByCurrency
            .map { Fmt.money($0.amount, currencyCode: $0.currency, locale: profile.locale) }
            .joined(separator: " + ")
        draw(
            totals.isEmpty ? "—" : totals,
            in: CGRect(x: columnX(4), y: cursor + 4, width: columns[4] + columns[5] + columns[6] - 5, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 9, weight: .bold),
            alignment: .right
        )
        return cursor + 22
    }

    private func drawDisclaimer(profile: ReportProfile, data: ReportData, at y: CGFloat) {
        let t = LocalizedStrings(locale: profile.locale)
        var cursor = y
        let generatedOn = Date.now.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(profile.locale)
        )
        var lines = [
            t.format("pdf.footer.generated", generatedOn),
            t.format(
                "pdf.footer.rule",
                profile.countryName, profile.countryCode, profile.ruleDescription, profile.ruleVersion
            ),
        ]
        if let source = profile.ruleSourceURL {
            lines.append(t.format("pdf.footer.source", source.absoluteString))
        }
        if data.isMixedCurrency {
            lines.append(t.format("pdf.footer.mixed.currency", data.totalsByCurrency.map(\.currency).joined(separator: ", ")))
        }
        if data.ruleVersions.count > 1 {
            lines.append(t.format("pdf.footer.mixed.versions", data.ruleVersions.joined(separator: ", ")))
        }
        if !profile.isOfficialRate {
            lines.append(t("pdf.footer.custom.rate"))
        }
        lines.append(t("pdf.footer.disclaimer"))

        for line in lines {
            let height = draw(
                line,
                in: CGRect(x: margin, y: cursor, width: contentWidth, height: 0),
                font: .systemFont(ofSize: 7.5),
                color: .secondaryLabel,
                wraps: true
            )
            cursor += height + 3
        }
    }

    private func drawPageFooter(profile: ReportProfile, page: Int, of total: Int) {
        let t = LocalizedStrings(locale: profile.locale)
        draw(
            "Mileage Pocket",
            in: CGRect(x: margin, y: pageSize.height - margin + 8, width: contentWidth / 2, height: 12),
            font: .systemFont(ofSize: 7.5),
            color: .tertiaryLabel
        )
        draw(
            t.format("pdf.page", page, total),
            in: CGRect(x: margin + contentWidth / 2, y: pageSize.height - margin + 8, width: contentWidth / 2, height: 12),
            font: .systemFont(ofSize: 7.5),
            color: .tertiaryLabel,
            alignment: .right
        )
    }

    // MARK: - Drawing primitives

    /// - Returns: the height this row actually occupied, so a wrapped value pushes the next
    ///   label down instead of being overlapped by it.
    @discardableResult
    private func drawLabelledValue(_ label: String, _ value: String, at point: CGPoint, width: CGFloat, wraps: Bool = false) -> CGFloat {
        draw(label.uppercased(), at: point, font: .systemFont(ofSize: 7.5, weight: .semibold), color: .secondaryLabel)
        let valueHeight = draw(
            value,
            in: CGRect(x: point.x, y: point.y + 11, width: width, height: wraps ? 0 : 14),
            font: .systemFont(ofSize: wraps ? 9 : 10.5, weight: .medium),
            wraps: wraps
        )
        return 11 + max(14, valueHeight) + 3
    }

    private func drawRule(y: CGFloat) {
        UIColor.systemGray4.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.5)).fill()
    }

    private func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor = .label) {
        attributed(text, font: font, color: color).draw(at: point)
    }

    /// - Parameter wraps: table cells truncate to keep a column's width; prose wraps, because
    ///   a disclaimer cut off mid-sentence is worse than one that takes an extra line — and
    ///   it fails silently, which is how it survives review.
    @discardableResult
    private func draw(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor = .label,
        alignment: NSTextAlignment = .left,
        wraps: Bool = false
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        let string = attributed(text, font: font, color: color, paragraph: paragraph)
        let bounding = string.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        string.draw(with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(rect.height, bounding.height)), options: [.usesLineFragmentOrigin], context: nil)
        return bounding.height
    }

    /// No `kern` anywhere in this document. Letter-spacing looks good on screen, but Core
    /// Text writes each spaced glyph separately and PDF text extraction then yields
    /// "M I L E A G E   R E P O R T" — the title stops being findable with Cmd-F, and a
    /// screen reader spells it out. A report exists to be read and searched.
    private func attributed(
        _ text: String,
        font: UIFont,
        color: UIColor,
        paragraph: NSParagraphStyle? = nil
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let paragraph { attributes[.paragraphStyle] = paragraph }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
