//
//  ReportRenderer.swift
//  Resonance
//
//  Care Report (PLAN.pdf Section 15): a one-page summary of trends for the care team,
//  rendered from a SwiftUI view into a US Letter PDF (612 x 792 points).
//

import SwiftUI
import Charts

struct ReportContent {
    var name: String
    var generated: Date
    var snapshot: InsightsSnapshot
    var firstDate: Date?
    var lastDate: Date?
    var breathingAlerts: Int
    var notes: [String]
    var isDemo: Bool
    /// Open "Questions for my care team", oldest first.
    var questions: [String] = []
}

/// The printable page (US Letter, light mode only, brand colors).
struct ReportView: View {
    let content: ReportContent

    private let violet = Color(hex: 0x5B3FD9)
    private let ink = Color(hex: 0x1B1530)

    private var rows: [MetricInsight] {
        // Flagged measures first, then the Function Index measures; at most 12 so the page never overflows.
        let flagged = content.snapshot.insights.filter { $0.status == .noticeableChange }
        let index = content.snapshot.insights.filter { $0.def.inIndex && $0.status != .noticeableChange }
        // Fewer rows when there are questions to print, so everything fits on one page.
        return Array((flagged + index).prefix(content.questions.isEmpty ? 12 : 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header band
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Resonance Care Report")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(content.name.isEmpty ? "Name not set" : content.name)
                        .font(.system(size: 13, weight: .medium))
                    if let first = content.firstDate, let last = content.lastDate {
                        Text("Check-ins from \(first.formatted(date: .abbreviated, time: .omitted)) to \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 10))
                            .opacity(0.85)
                    }
                }
                Spacer()
                if let index = content.snapshot.functionIndex {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Function Index").font(.system(size: 10, weight: .medium)).opacity(0.85)
                        Text("\(Int(index.rounded()))")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("100 = own baseline").font(.system(size: 8)).opacity(0.8)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(LinearGradient(colors: [Color(hex: 0x6A4CF0), violet, Color(hex: 0x2C1A86)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if content.isDemo {
                Text("Sample data: this report was made from demo check-ins, not real measurements.")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8A5300))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xE8962E).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

            if content.snapshot.history.count >= 2 {
                Chart(content.snapshot.history) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Index", p.index))
                        .foregroundStyle(violet.opacity(0.12))
                    LineMark(x: .value("Date", p.date), y: .value("Index", p.index))
                        .foregroundStyle(violet)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Date", p.date), y: .value("Index", p.index))
                        .foregroundStyle(violet)
                        .symbolSize(18)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 100)
            }

            Text("Measurements compared with this person's own baseline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink)

            VStack(spacing: 0) {
                reportRow("Measure", "Baseline", "Latest", "Change*", "Status", header: true)
                ForEach(rows, id: \.def.key) { i in
                    reportRow(
                        "\(i.def.name) (\(i.def.unit))",
                        i.baseline.map { InsightsEngine.format($0) } ?? "-",
                        InsightsEngine.format(i.latest),
                        changeCell(i),
                        i.status.rawValue,
                        flagged: i.status == .noticeableChange
                    )
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.35), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("*Change compared with the person's own baseline: positive = better, negative = worse.")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            if let score = content.snapshot.insights.first(where: { $0.def.key == MetricKey.speechChangeScore }) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(SpeechChangeModel.title): latest \(Int(score.latest.rounded())) / 100")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(violet)
                    Text(SpeechChangeModel.explanation)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // A short summary that always fits; the table above has the details.
            VStack(alignment: .leading, spacing: 3) {
                Text("Summary: \(content.snapshot.headline)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink)
                if content.snapshot.insights.contains(where: { $0.status == .noticeableChange }) {
                    Text("Measures marked \"Noticeable change\" have changed more than the person's usual day-to-day variation. It may be worth discussing them with the care team.")
                        .font(.system(size: 10))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if content.breathingAlerts > 0 {
                Text("Breathing alerts in this period: \(content.breathingAlerts). The person was advised to contact their care team.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC4363B))
            }

            if !content.questions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Questions for this visit").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                    ForEach(Array(content.questions.prefix(CareQuestions.reportLimit).enumerated()), id: \.offset) { item in
                        Text("\(item.offset + 1). \(item.element)").font(.system(size: 10)).foregroundStyle(ink).lineLimit(1)
                    }
                    if content.questions.count > CareQuestions.reportLimit {
                        Text("+ \(content.questions.count - CareQuestions.reportLimit) more in the app")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }

            if !content.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                    ForEach(content.notes.prefix(content.questions.isEmpty ? 3 : 1), id: \.self) { note in
                        Text("• \(note)").font(.system(size: 10)).foregroundStyle(ink).lineLimit(content.questions.isEmpty ? 2 : 1)
                    }
                }
            }
        }
        .padding(32)
        .padding(.bottom, 28)   // room for the footer below
        .frame(width: 612, height: 792, alignment: .topLeading)
        // The disclaimer is pinned to the bottom of the page so it is never pushed off.
        .overlay(alignment: .bottomLeading) {
            Text("Generated by Resonance, a student-built monitoring app, on \(content.generated.formatted(date: .abbreviated, time: .shortened)). Measurements are estimates from a phone and are not a diagnosis.")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .background(Color.white)
        }
        .clipped()
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// "+5%" / "-28%" for most measures; points for scores that are already 0-100.
    private func changeCell(_ i: MetricInsight) -> String {
        if i.def.unit == "/100", let baseline = i.baseline {
            let diff = Int((i.latest - baseline).rounded())
            return diff == 0 ? "same" : "\(abs(diff)) \(diff > 0 ? "higher" : "lower")"
        }
        return i.changePct.map { String(format: "%+.0f%%", $0) } ?? "-"
    }

    private func reportRow(_ a: String, _ b: String, _ c: String, _ d: String, _ e: String,
                           header: Bool = false, flagged: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(a).frame(width: 210, alignment: .leading)
            Text(b).frame(width: 70, alignment: .trailing)
            Text(c).frame(width: 70, alignment: .trailing)
            Text(d).frame(width: 60, alignment: .trailing)
            Text(e).frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(flagged ? Color(hex: 0xB86A10) : ink)
        }
        .font(.system(size: 10, weight: header ? .semibold : .regular))
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(header ? violet.opacity(0.1) : (flagged ? Color(hex: 0xE8962E).opacity(0.08) : Color.clear))
    }
}

enum ReportRenderer {
    /// Renders the report to a PDF file in the temporary folder and returns its URL.
    @MainActor
    static func renderPDF(_ content: ReportContent) -> URL? {
        let renderer = ImageRenderer(content: ReportView(content: content))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Resonance-Care-Report.pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            // Center the content if its size differs slightly from the page.
            pdf.translateBy(x: (612 - size.width) / 2, y: (792 - size.height) / 2)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}
