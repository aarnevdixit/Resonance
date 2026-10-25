//
//  ReportPreviewView.swift
//  Resonance
//
//  Shows the Care Report and lets the person export or share it as a PDF.
//

import SwiftUI
import SwiftData

struct ReportPreviewView: View {
    @Query(sort: \VoiceSession.date) private var voice: [VoiceSession]
    @Query(sort: \MotorSession.date) private var motor: [MotorSession]
    @Query(sort: \FunctionCheck.date) private var checks: [FunctionCheck]
    @Query private var profiles: [Profile]
    @Query(sort: \CareQuestion.createdAt) private var questions: [CareQuestion]
    @State private var pdfURL: URL?

    private var content: ReportContent {
        let records = InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
        let dates = records.map(\.date)
        let breathing = checks.filter {
            $0.answers.count == 8 && $0.answers[FunctionQuestions.breathingIndex] <= 1
        }.count
        let notes = checks.reversed().compactMap(\.note)
        return ReportContent(
            name: profiles.first?.name ?? "",
            generated: Date(),
            snapshot: InsightsBuilder.snapshot(from: records),
            firstDate: dates.min(),
            lastDate: dates.max(),
            breathingAlerts: breathing,
            notes: Array(notes),
            isDemo: voice.contains(where: \.isDemo) || motor.contains(where: \.isDemo),
            questions: CareQuestions.open(questions.map { (text: $0.text, createdAt: $0.createdAt, asked: $0.asked) })
        )
    }

    var body: some View {
        let content = self.content
        ScrollView([.vertical, .horizontal]) {
            ReportView(content: content)
                .scaleEffect(0.6, anchor: .topLeading)
                .frame(width: 612 * 0.6, height: 792 * 0.6, alignment: .topLeading)
                .shadow(radius: 4)
                .padding()
        }
        .background(Color(.systemGroupedBackground))
        .screenBackground()
        .navigationTitle("Care Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Make PDF") {
                        pdfURL = ReportRenderer.renderPDF(content)
                    }
                }
            }
        }
    }
}
