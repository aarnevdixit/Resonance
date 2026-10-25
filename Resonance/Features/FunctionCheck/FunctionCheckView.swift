//
//  FunctionCheckView.swift
//  Resonance
//
//  Daily Function Check (PLAN.pdf Section 11): eight questions, one per screen,
//  big answer buttons (4 = normal ... 0 = unable), then mood and an optional note.
//  These are original questions inspired by how ALS clinics track function;
//  they are not the official clinical scale.
//

import SwiftUI
import SwiftData

struct FunctionQuestion {
    let text: String
    let labels: [String]   // index 0...4 = answer 4...0 (shown top to bottom, best first)
}

enum FunctionQuestions {
    static let all: [FunctionQuestion] = [
        .init(text: "How is your speech today?",
              labels: ["Normal", "Mostly normal", "Others sometimes ask me to repeat", "Very hard to understand", "I can't be understood"]),
        .init(text: "How is swallowing and saliva today?",
              labels: ["Normal", "Mostly normal", "Some coughing or drooling", "Very hard", "I can't swallow safely"]),
        .init(text: "How are writing and small hand tasks (buttons, phone)?",
              labels: ["Normal", "Mostly normal", "Slow or clumsy", "Very hard", "I can't do them"]),
        .init(text: "How are dressing and personal care?",
              labels: ["Normal", "Mostly normal", "I need some help", "Very hard", "I need full help"]),
        .init(text: "How is walking?",
              labels: ["Normal", "Mostly normal", "I use a cane or walker", "Very hard", "I can't walk"]),
        .init(text: "How are stairs?",
              labels: ["Normal", "Mostly normal", "Slow, need the rail", "Very hard", "I can't do stairs"]),
        .init(text: "How is breathing when lying down or active?",
              labels: ["Normal", "Mostly normal", "Short of breath sometimes", "Very hard", "I need breathing support"]),
        .init(text: "How is your energy (fatigue)?",
              labels: ["Normal", "Mostly normal", "Tired by midday", "Very hard", "Too tired for most things"]),
    ]

    static let breathingIndex = 6
}

struct FunctionCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FunctionCheck.date, order: .reverse) private var previousChecks: [FunctionCheck]

    @State private var index = 0
    @State private var answers: [Int] = []
    @State private var mood: Int?
    @State private var note = ""
    @State private var saved = false
    @State private var showBreathingWarning = false

    private var questions: [FunctionQuestion] { FunctionQuestions.all }
    private var onMoodScreen: Bool { index == questions.count }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(min(index, questions.count)), total: Double(questions.count))
                .tint(AppTheme.accent)
                .padding(.horizontal, AppTheme.padding)
                .padding(.top, 8)
                .accessibilityLabel("Question \(min(index + 1, questions.count)) of \(questions.count)")

            ScrollView {
                VStack(spacing: 16) {
                    if showBreathingWarning {
                        // Required safety message (PLAN.pdf Section 11). Always shown when the rule triggers.
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(systemImage: "lungs.fill", color: AppTheme.coral, size: 44)
                            Text(BreathingSafety.message)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(AppTheme.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.coral.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                            .stroke(AppTheme.coral.opacity(0.35), lineWidth: 1.5))
                        .accessibilityElement(children: .combine)
                    }

                    if saved {
                        savedView
                    } else if onMoodScreen {
                        moodView
                    } else {
                        questionView(questions[index])
                            .id(index)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                .padding(AppTheme.padding)
            }
        }
        .screenBackground()
        .navigationTitle("Function Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func questionView(_ question: FunctionQuestion) -> some View {
        VStack(spacing: 14) {
            Text("Question \(index + 1) of \(questions.count)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(question.text)
                .font(.system(.title, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

            ForEach(0..<5, id: \.self) { position in
                let score = 4 - position
                Button {
                    answer(score)
                } label: {
                    HStack(spacing: 14) {
                        Text("\(score)")
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(color(for: score), in: Circle())
                        Text(question.labels[position])
                            .font(.title3)
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .surfaceStyle(radius: AppTheme.controlRadius)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(question.labels[position]), score \(score)")
            }

            if index > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        index -= 1
                        answers.removeLast()
                        showBreathingWarning = false
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    private var moodView: some View {
        VStack(spacing: 16) {
            Text("How is your mood today?")
                .font(.system(.title, design: .rounded).weight(.bold))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        mood = value
                    } label: {
                        Text(moodFace(value))
                            .font(.system(size: 40))
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(mood == value ? AppTheme.violetSoft : AppTheme.surface,
                                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                .stroke(mood == value ? AppTheme.accent : .clear, lineWidth: 2.5))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(mood == value ? .isSelected : [])
                    .accessibilityLabel(moodName(value))
                }
            }

            TextField("Anything else to note? (optional)", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .padding(14)
                .surfaceStyle(radius: AppTheme.controlRadius)

            Button("Save") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(mood == nil)

            // Lets the person change their last answer instead of starting over.
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    index -= 1
                    answers.removeLast()
                    showBreathingWarning = false
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var savedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.mint)
                .symbolEffect(.bounce, value: saved)
                .accessibilityHidden(true)
            Text("Saved. Thank you.")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Total: \(answers.reduce(0, +)) of 32")
                .font(.title3)
            Button("Close") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
            NextStepsPanel(limit: 3)
                .padding(.top, 8)
        }
    }

    // MARK: Actions

    private func answer(_ score: Int) {
        // Guard against a double tap answering the next question too.
        guard answers.count == index, index < questions.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            answers.append(score)
            if index == FunctionQuestions.breathingIndex {
                // Compare with the person's own last real check (never demo data).
                let previous = previousChecks
                    .first(where: { !$0.isDemo && $0.answers.count == questions.count })?
                    .answers[FunctionQuestions.breathingIndex]
                showBreathingWarning = BreathingSafety.shouldWarn(current: score, previous: previous)
            }
            index += 1
        }
    }

    private func save() {
        // A double tap must never save the same check-in twice.
        guard !saved, let mood, answers.count == questions.count else { return }
        let check = FunctionCheck(date: Date(), answers: answers, mood: mood)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        check.note = trimmed.isEmpty ? nil : trimmed
        modelContext.insert(check)
        try? modelContext.save()
        saved = true
    }

    // MARK: Helpers

    private func color(for score: Int) -> Color {
        switch score {
        // A single violet ramp: darker means more function. No red: a low answer is not an alarm.
        case 4: return AppTheme.violetDeep
        case 3: return Color(hex: 0x4A33C4)
        case 2: return Color(hex: 0x6A55D6)
        case 1: return Color(hex: 0x8A79DE)
        default: return .gray
        }
    }

    private func moodFace(_ value: Int) -> String {
        ["😞", "🙁", "😐", "🙂", "😄"][value - 1]
    }

    private func moodName(_ value: Int) -> String {
        ["Very low", "Low", "Okay", "Good", "Very good"][value - 1]
    }
}

#Preview {
    NavigationStack { FunctionCheckView() }
        .modelContainer(for: FunctionCheck.self, inMemory: true)
}
