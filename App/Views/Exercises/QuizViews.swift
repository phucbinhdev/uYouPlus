import PianoCore
import SwiftUI

/// Đọc nốt trên khuông và chọn tên đúng (có thể trả lời bằng cách đánh nốt đó trên đàn).
struct NameQuizView: View {
    let exercise: Exercise
    let isActive: Bool
    let onFinish: (ExerciseResult) -> Void

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var input: NoteInput
    @EnvironmentObject private var synth: SynthEngine
    @State private var selected: Int?
    @State private var checked = false

    private var answer: Pitch {
        if case .nameQuiz(let p, _) = exercise.kind { return p }
        return Pitch.middleC
    }

    private var choices: [Pitch] {
        if case .nameQuiz(_, let c) = exercise.kind { return c }
        return []
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(exercise.title(app.settings.naming))
                .font(.rounded(28, .heavy))
                .foregroundColor(.duoText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            HStack(spacing: 24) {
                MascotView(mood: checked ? (isCorrect ? .excited : .sad) : .thinking, size: 100)
                StaffView(clef: Clef.best(for: [answer]),
                          notes: [StaffNote(id: 0, x: 0, pitches: [answer], duration: 4,
                                            color: checked ? (isCorrect ? .duoGreen : .duoRed) : .duoText)],
                          centerContent: true, showLabels: false)
                    .frame(maxWidth: 420, maxHeight: 240)
                    .card(padding: 8)
            }
            .frame(maxHeight: .infinity)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(Array(choices.enumerated()), id: \.offset) { i, p in
                    Button {
                        guard !checked else { return }
                        selected = i
                        synth.play(p.midi, duration: 0.5)
                        Haptics.tap()
                    } label: {
                        Text(p.name(app.settings.naming))
                    }
                    .buttonStyle(DuoChoiceStyle(selected: selected == i, state: state(for: i)))
                }
            }
            .frame(maxWidth: 640)

            Text("Mẹo: bạn cũng có thể trả lời bằng cách đánh nốt đó trên đàn.")
                .font(.rounded(15, .semibold))
                .foregroundColor(.duoGrayDark)

            Button("Kiểm tra", action: check)
                .buttonStyle(DuoButtonStyle())
                .disabled(selected == nil || checked || !isActive)
                .frame(maxWidth: 640)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 28)
        .onReceive(input.events) { e in
            guard e.isOn, isActive, !checked else { return }
            if let idx = choices.firstIndex(where: { $0.pitchClass == e.pitch.pitchClass }) {
                selected = idx
            }
        }
    }

    private var isCorrect: Bool {
        guard let s = selected else { return false }
        return choices[s].pitchClass == answer.pitchClass
    }

    private func state(for i: Int) -> DuoChoiceStyle.ChoiceState {
        guard checked else { return .normal }
        if choices[i].pitchClass == answer.pitchClass { return .correct }
        if i == selected { return .wrong }
        return .normal
    }

    private func check() {
        guard selected != nil else { return }
        checked = true
        synth.play(answer.midi, duration: 0.7)
        onFinish(ExerciseResult(success: isCorrect, mistakes: isCorrect ? 0 : 1,
                                detail: isCorrect ? nil : "Đáp án đúng: \(answer.name(app.settings.naming))"))
    }
}

/// Câu hỏi lý thuyết trắc nghiệm.
struct TheoryQuizView: View {
    let exercise: Exercise
    let isActive: Bool
    let onFinish: (ExerciseResult) -> Void

    @State private var selected: Int?
    @State private var checked = false

    private var parts: (question: String, choices: [String], answer: Int, explanation: String?) {
        if case .theory(let q, let c, let a, let e) = exercise.kind { return (q, c, a, e) }
        return ("", [], 0, nil)
    }

    var body: some View {
        let p = parts
        VStack(spacing: 22) {
            Text("Câu hỏi")
                .font(.rounded(18, .heavy))
                .foregroundColor(.duoPurple)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            HStack(alignment: .center, spacing: 20) {
                MascotView(mood: checked ? (selected == p.answer ? .excited : .sad) : .thinking, size: 100)
                SpeechBubble {
                    Text(p.question)
                        .font(.rounded(24, .heavy))
                        .foregroundColor(.duoText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                ForEach(Array(p.choices.enumerated()), id: \.offset) { i, choice in
                    Button {
                        guard !checked else { return }
                        selected = i
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 14) {
                            Text("\(i + 1)")
                                .font(.rounded(16, .heavy))
                                .foregroundColor(.duoGrayDark)
                                .frame(width: 30, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.duoGray, lineWidth: 2))
                            Text(choice)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                    .buttonStyle(DuoChoiceStyle(selected: selected == i, state: state(for: i, answer: p.answer)))
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }
            .frame(maxWidth: 640)
            Spacer(minLength: 0)
            Button("Kiểm tra") {
                guard let s = selected else { return }
                checked = true
                let ok = s == p.answer
                onFinish(ExerciseResult(success: ok, mistakes: ok ? 0 : 1,
                                        detail: ok ? p.explanation : "Đáp án đúng: \(p.choices[p.answer])" + (p.explanation.map { "\n\($0)" } ?? "")))
            }
            .buttonStyle(DuoButtonStyle())
            .disabled(selected == nil || checked || !isActive)
            .frame(maxWidth: 640)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 28)
    }

    private func state(for i: Int, answer: Int) -> DuoChoiceStyle.ChoiceState {
        guard checked else { return .normal }
        if i == answer { return .correct }
        if i == selected { return .wrong }
        return .normal
    }
}
