//
//  CareQuestionsView.swift
//  Resonance
//
//  "Questions for my care team": write them down whenever they come up, tick them off at
//  the visit. Open questions also appear on the Care Report.
//

import SwiftUI
import SwiftData

struct CareQuestionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CareQuestion.createdAt) private var questions: [CareQuestion]
    @State private var draft = ""
    @State private var duplicate = false
    @Query private var profiles: [Profile]
    @FocusState private var typing: Bool

    private var open: [CareQuestion] { questions.filter { !$0.asked } }
    private var asked: [CareQuestion] { questions.filter(\.asked).reversed() }
    private var shareText: String? { CareQuestions.shareText(open.map(\.text)) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Type a question…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($typing)
                        .submitLabel(.done)
                        .frame(minHeight: AppTheme.minTapSize)
                        .accessibilityLabel("New question")
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(AppTheme.accent)
                            .frame(minWidth: AppTheme.minTapSize, minHeight: AppTheme.minTapSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(CareQuestions.clean(draft) == nil)
                    .accessibilityLabel("Add question")
                }
                if duplicate {
                    Label("That question is already on your list.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Tip: on the Talk board, type a question and tap Ask later, or touch and hold your message.")
            }

            Section {
                if open.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing to ask yet")
                            .font(.headline)
                        Text("Questions about breathing, eating, sleep, equipment or medicines are all worth writing down. They're easy to forget at the visit.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(open) { question in
                    QuestionRow(question: question, speak: { say(question.text) })
                }
                .onDelete { remove(open, $0) }
            } header: {
                Text("To ask")
            } footer: {
                if !open.isEmpty {
                    Text("Shown on your Care Report. Tap the circle when it's been answered.")
                }
            }

            if !asked.isEmpty {
                Section("Asked") {
                    ForEach(asked) { question in
                        QuestionRow(question: question, speak: { say(question.text) })
                    }
                    .onDelete { remove(asked, $0) }
                }
            }
        }
        .tint(AppTheme.accent)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Questions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareText {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityHint("Shares the questions you haven't asked yet")
                }
            }
        }
        .onChange(of: draft) { old, text in
            // A multi-line field turns the keyboard's Done key into a line break; treat it as Add.
            if text.contains("\n") {
                draft = text.replacingOccurrences(of: "\n", with: " ")
                add()
            } else if old.replacingOccurrences(of: "\n", with: " ") != text {
                duplicate = false   // the person is typing again
            }
        }
    }

    private func say(_ text: String) {
        SpeechOutput.shared.speak(text, rate: Float(profiles.first?.speechRate ?? 0.45))
    }

    private func add() {
        guard let text = CareQuestions.clean(draft) else { return }
        if let old = questions.first(where: { CareQuestions.isDuplicate(text, of: [$0.text]) }) {
            if old.asked {
                // Asked before but it came up again: put it back on the list.
                withAnimation(.snappy) { old.asked = false }
                try? modelContext.save()
                draft = ""
            } else {
                duplicate = true
            }
            return
        }
        modelContext.insert(CareQuestion(text: text))
        try? modelContext.save()
        draft = ""
    }

    private func remove(_ list: [CareQuestion], _ offsets: IndexSet) {
        for index in offsets where list.indices.contains(index) {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
    }
}

private struct QuestionRow: View {
    @Bindable var question: CareQuestion
    let speak: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { question.asked.toggle() }
            } label: {
                Image(systemName: question.asked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(question.asked ? AppTheme.mint : AppTheme.accent)
                    .frame(minWidth: AppTheme.minTapSize, minHeight: AppTheme.minTapSize)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(question.asked ? "Mark as not asked: \(question.text)" : "Mark as asked: \(question.text)")

            Text(question.text)
                .font(.body)
                .foregroundStyle(question.asked ? .secondary : AppTheme.ink)
                .strikethrough(question.asked, color: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: speak) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(minWidth: AppTheme.minTapSize, minHeight: AppTheme.minTapSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read out loud: \(question.text)")
        }
    }
}

/// Family tab card: how many questions are waiting, and the first one.
struct CareQuestionsCard: View {
    @Query(filter: #Predicate<CareQuestion> { !$0.asked }, sort: \CareQuestion.createdAt)
    private var open: [CareQuestion]

    var body: some View {
        NavigationLink {
            CareQuestionsView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "questionmark.bubble.fill", color: AppTheme.amber, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Questions for my care team")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(open.isEmpty ? "Write them down before the next visit"
                                          : "\(open.count) to ask at the next visit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if let first = open.first {
                    Text("“\(first.text)”")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.amber.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(AppTheme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceStyle()
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    NavigationStack { CareQuestionsView() }
        .modelContainer(for: CareQuestion.self, inMemory: true)
}
