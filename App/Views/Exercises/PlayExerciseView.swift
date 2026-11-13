import Combine
import PianoCore
import QuartzCore
import SwiftUI

/// Chọn màn hình phù hợp cho từng loại bài tập.
struct ExerciseHost: View {
    let exercise: Exercise
    let isActive: Bool
    let onFinish: (ExerciseResult) -> Void
    @EnvironmentObject private var app: AppModel

    var body: some View {
        switch exercise.kind {
        case .introduce, .findKey, .earTraining, .sequence, .chord:
            PlayExerciseView(exercise: exercise, strictOctave: app.settings.strictOctave, isActive: isActive, onFinish: onFinish)
        case .nameQuiz:
            NameQuizView(exercise: exercise, isActive: isActive, onFinish: onFinish)
        case .theory:
            TheoryQuizView(exercise: exercise, isActive: isActive, onFinish: onFinish)
        case .rhythm(let pattern):
            RhythmExerciseView(pattern: pattern, isActive: isActive, onFinish: onFinish)
        }
    }
}

final class PlayExerciseModel: ObservableObject {
    let exercise: Exercise
    let evaluator: StepEvaluator
    /// Các nốt (kể cả dấu lặng) của bài chuỗi nốt / hợp âm để vẽ khuông.
    let scoreNotes: [ScoreNote]
    /// Chỉ số nốt trong `scoreNotes` ứng với từng bước.
    let noteIndexForStep: [Int]

    @Published private(set) var keyColors: [Int: Color] = [:]
    @Published private(set) var stepIndex = 0
    @Published private(set) var mistakesOnStep = 0
    @Published private(set) var totalMistakes = 0
    @Published private(set) var shake: CGFloat = 0
    @Published private(set) var finished = false
    @Published private(set) var mood: MascotView.Mood = .thinking
    @Published private(set) var remaining: [Pitch] = []

    init(exercise: Exercise, strictOctave: Bool) {
        self.exercise = exercise
        evaluator = StepEvaluator(exercise: exercise, strictOctave: strictOctave)
        switch exercise.kind {
        case .sequence(_, let notes):
            scoreNotes = notes
        case .chord(_, let pitches):
            scoreNotes = [ScoreNote(pitches: pitches, beat: 0, duration: 4)]
        case .introduce(let p, _), .findKey(let p, _), .earTraining(let p, _):
            scoreNotes = [ScoreNote(pitches: [p], beat: 0, duration: 4)]
        default:
            scoreNotes = []
        }
        noteIndexForStep = scoreNotes.enumerated().filter { !$0.element.isRest }.map(\.offset)
        remaining = evaluator.remainingInStep
    }

    var totalSteps: Int { evaluator.steps.count }

    func handle(_ event: NoteEvent) -> ExerciseOutcome? {
        if !event.isOn {
            evaluator.noteOff(event.pitch)
            keyColors[event.pitch.midi] = nil
            remaining = evaluator.remainingInStep
            return nil
        }
        guard !finished, let fb = evaluator.noteOn(event.pitch) else { return nil }
        if fb.isCorrect {
            keyColors[event.pitch.midi] = .duoGreen
            if fb.completedStep != nil {
                stepIndex = evaluator.stepIndex
                mistakesOnStep = 0
                mood = .happy
            }
        } else {
            keyColors[event.pitch.midi] = .duoRed
            mistakesOnStep += 1
            totalMistakes += 1
            mood = .sad
            withAnimation(.default) { shake += 1 }
        }
        remaining = evaluator.remainingInStep
        if let outcome = fb.outcome {
            finished = true
            mood = .excited
            return outcome
        }
        return nil
    }

    /// Phím gợi ý (tô xanh) trên bàn phím.
    var hintKeys: [Int] {
        guard !finished else { return [] }
        let showHints = exercise.showHints
        switch exercise.kind {
        case .introduce:
            return remaining.map(\.midi)
        case .findKey:
            return showHints && mistakesOnStep >= 1 ? remaining.map(\.midi) : []
        case .earTraining:
            return showHints && mistakesOnStep >= 2 ? remaining.map(\.midi) : []
        case .sequence:
            return (showHints || mistakesOnStep >= 2) ? remaining.map(\.midi) : []
        case .chord:
            return remaining.map(\.midi)
        default:
            return []
        }
    }

    var currentNoteIndex: Int? {
        stepIndex < noteIndexForStep.count ? noteIndexForStep[stepIndex] : nil
    }
}

/// Bài tập chơi đàn: giới thiệu nốt, tìm phím, nghe và đánh lại, chuỗi nốt, hợp âm.
struct PlayExerciseView: View {
    let exercise: Exercise
    let isActive: Bool
    let onFinish: (ExerciseResult) -> Void

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var input: NoteInput
    @EnvironmentObject private var synth: SynthEngine
    @StateObject private var model: PlayExerciseModel

    init(exercise: Exercise, strictOctave: Bool, isActive: Bool, onFinish: @escaping (ExerciseResult) -> Void) {
        self.exercise = exercise
        self.isActive = isActive
        self.onFinish = onFinish
        _model = StateObject(wrappedValue: PlayExerciseModel(exercise: exercise, strictOctave: strictOctave))
    }

    private var naming: NoteNaming { app.settings.naming }

    var body: some View {
        GeometryReader { geo in
            let keyboardHeight = min(270, max(170, geo.size.height * 0.33))
            VStack(spacing: 14) {
                Text(exercise.title(naming))
                    .font(.rounded(28, .heavy))
                    .foregroundColor(.duoText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                prompt
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(ShakeEffect(animatableData: model.shake))
                    .padding(.horizontal, 28)

                statusLine
                    .padding(.horizontal, 28)

                PianoKeyboardView(
                    range: keyboardRange(for: exercise.involvedPitches),
                    pressed: input.held,
                    keyColors: model.keyColors,
                    hints: Dictionary(uniqueKeysWithValues: model.hintKeys.map { ($0, Color.duoBlue) }),
                    naming: naming,
                    labelAllKeys: app.settings.showKeyLabels && exercise.showHints,
                    fingers: fingerHints,
                    onNoteOn: { input.touchDown($0) },
                    onNoteOff: { input.touchUp($0) }
                )
                .frame(height: keyboardHeight)
                .padding(.horizontal, 12)

                bottomBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }
        }
        .onReceive(input.events) { event in
            guard isActive else {
                if !event.isOn { _ = model.handle(event) }
                return
            }
            if let outcome = model.handle(event) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFinish(result(for: outcome))
                }
            }
        }
        .onAppear {
            if case .earTraining(let p, _) = exercise.kind {
                synth.play(p.midi, duration: 0.9, delay: 0.5)
            }
        }
    }

    private func result(for outcome: ExerciseOutcome) -> ExerciseResult {
        var detail: String?
        if !outcome.success {
            switch exercise.kind {
            case .earTraining(let p, _): detail = "Nốt bạn vừa nghe là \(p.name(naming))."
            case .findKey(let p, _): detail = "Đó là nốt \(p.name(naming)). Bài này sẽ được làm lại sau."
            default: detail = nil
            }
        }
        return ExerciseResult(success: outcome.success, mistakes: outcome.mistakes, detail: detail)
    }

    private var fingerHints: [Int: Int] {
        guard app.settings.showFingers, let idx = model.currentNoteIndex, idx < model.scoreNotes.count,
              let finger = model.scoreNotes[idx].finger else { return [:] }
        var map: [Int: Int] = [:]
        for p in model.remaining { map[p.midi] = finger }
        return map
    }

    // MARK: Đề bài

    @ViewBuilder private var prompt: some View {
        switch exercise.kind {
        case .introduce(let p, let tip):
            HStack(alignment: .center, spacing: 24) {
                VStack(spacing: 12) {
                    MascotView(mood: model.mood, size: 110)
                    playButton { synth.play(p.midi, duration: 0.9) }
                }
                VStack(alignment: .leading, spacing: 16) {
                    SpeechBubble {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(p.name(naming))
                                .font(.rounded(40, .heavy))
                                .foregroundColor(.duoBlue)
                            Text(tip)
                                .font(.rounded(19, .semibold))
                                .foregroundColor(.duoText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    staff(labels: true)
                        .frame(maxWidth: 360, maxHeight: 170)
                }
            }
        case .findKey(let p, let style):
            switch style {
            case .name:
                HStack(spacing: 24) {
                    MascotView(mood: model.mood, size: 120)
                    SpeechBubble {
                        VStack(spacing: 4) {
                            Text(p.solfegeName())
                                .font(.rounded(64, .heavy))
                                .foregroundColor(.duoBlue)
                            if naming != .solfege {
                                Text(p.letterName())
                                    .font(.rounded(30, .heavy))
                                    .foregroundColor(.duoSubtext)
                            }
                        }
                        .frame(minWidth: 150)
                    }
                }
            case .staff:
                VStack(spacing: 8) {
                    staff(labels: false)
                        .frame(maxWidth: 420, maxHeight: 230)
                        .card(padding: 8)
                    Text("Nốt này là phím nào trên đàn?")
                        .font(.rounded(18, .semibold))
                        .foregroundColor(.duoSubtext)
                }
            case .nameAndStaff:
                HStack(spacing: 24) {
                    MascotView(mood: model.mood, size: 100)
                    staff(labels: true)
                        .frame(maxWidth: 420, maxHeight: 230)
                        .card(padding: 8)
                }
            }
        case .earTraining(let p, _):
            VStack(spacing: 18) {
                Button {
                    synth.play(p.midi, duration: 0.9)
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 54, weight: .bold))
                        .frame(width: 130, height: 110)
                }
                .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 110, fullWidth: false))
                Text("Bấm để nghe lại. Đánh đúng tên nốt, quãng tám nào cũng được.")
                    .font(.rounded(18, .semibold))
                    .foregroundColor(.duoSubtext)
                    .multilineTextAlignment(.center)
            }
        case .sequence(_, let notes):
            VStack(spacing: 10) {
                GeometryReader { g in
                    let s = g.size.height / 13
                    let spacing: CGFloat = notes.contains { $0.pitches.contains { $0.isBlack } } ? 3.7 : 3.2
                    let visible = max(4, (g.size.width - s * 5.2) / max(1, s))
                    let currentX = CGFloat(model.currentNoteIndex ?? (notes.count - 1)) * spacing
                    let contentWidth = CGFloat(notes.count) * spacing
                    let scroll = contentWidth > visible ? min(max(0, currentX - visible * 0.3), contentWidth - visible + 2) : 0
                    StaffView(clef: Clef.best(for: notes.flatMap(\.pitches)),
                              notes: staffNotes(notes, spacing: spacing),
                              scroll: scroll,
                              centerContent: contentWidth <= visible,
                              showLabels: true)
                        .animation(.easeInOut(duration: 0.3), value: scroll)
                }
                .frame(maxHeight: 250)
                .card(padding: 8)
                HStack(spacing: 14) {
                    playButton { playSequence(notes) }
                    Text("Nghe mẫu")
                        .font(.rounded(17, .bold))
                        .foregroundColor(.duoBlue)
                }
            }
        case .chord(let name, let pitches):
            HStack(spacing: 28) {
                VStack(spacing: 10) {
                    MascotView(mood: model.mood, size: 100)
                    playButton {
                        for p in pitches { synth.play(p.midi, duration: 1.2) }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(name)
                        .font(.rounded(34, .heavy))
                        .foregroundColor(.duoBlue)
                    Text(pitches.map { $0.name(naming) }.joined(separator: " – "))
                        .font(.rounded(20, .bold))
                        .foregroundColor(.duoSubtext)
                    staff(labels: false)
                        .frame(maxWidth: 300, maxHeight: 190)
                        .card(padding: 6)
                }
            }
        default:
            EmptyView()
        }
    }

    private func staff(labels: Bool) -> some View {
        let notes = model.scoreNotes
        return StaffView(clef: Clef.best(for: notes.flatMap(\.pitches)),
                         notes: staffNotes(notes, spacing: 3.2, forceLabels: labels),
                         centerContent: true,
                         showLabels: labels)
    }

    private func staffNotes(_ notes: [ScoreNote], spacing: CGFloat, forceLabels: Bool? = nil) -> [StaffNote] {
        let current = model.currentNoteIndex
        let showLabels = forceLabels ?? (app.settings.showNoteNames && exercise.showHints)
        return notes.enumerated().map { i, n in
            var color = Color.duoText
            if let c = current {
                if i < c { color = .duoGreen } else if i == c { color = .duoBlue }
            } else if model.finished {
                color = .duoGreen
            }
            if n.isRest { color = .duoGrayDark }
            let label = showLabels && !n.isRest ? n.pitches.map { $0.shortName(naming) }.joined(separator: "·") : nil
            return StaffNote(id: i, x: CGFloat(i) * spacing, pitches: n.pitches, duration: n.duration, color: color,
                             label: label, finger: app.settings.showFingers ? n.finger : nil,
                             highlight: notes.count > 1 && i == current)
        }
    }

    private func playButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 30)
        }
        .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 48, fullWidth: false))
        .accessibilityLabel("Nghe")
    }

    private func playSequence(_ notes: [ScoreNote]) {
        let spb = 0.6
        let items = notes.filter { !$0.isRest }.map { n in
            (midi: n.pitches.map(\.midi), start: n.beat * spb, duration: n.duration * spb)
        }
        synth.schedule(notes: items, startTime: CACurrentMediaTime() + 0.1)
    }

    // MARK: Trạng thái và nút dưới

    @ViewBuilder private var statusLine: some View {
        HStack(spacing: 10) {
            switch exercise.kind {
            case .sequence:
                Image(systemName: "music.note")
                Text("Đã đúng \(model.stepIndex)/\(model.totalSteps) nốt")
            case .chord:
                Image(systemName: "hand.raised.fingers.spread.fill")
                Text("Nhấn và giữ cùng lúc các phím sáng màu xanh")
            case .introduce:
                Image(systemName: "hand.point.down.fill")
                Text("Nhấn phím đang sáng màu xanh")
            default:
                if model.mistakesOnStep > 0 && !model.hintKeys.isEmpty {
                    Image(systemName: "lightbulb.fill").foregroundColor(.duoYellow)
                    Text("Gợi ý: phím đúng đang sáng màu xanh")
                } else if model.mistakesOnStep > 0 {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Chưa đúng, thử lại nhé!")
                } else {
                    Image(systemName: "pianokeys")
                    Text("Đánh trên đàn hoặc chạm vào bàn phím bên dưới")
                }
            }
            Spacer()
        }
        .font(.rounded(17, .bold))
        .foregroundColor(.duoSubtext)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                let skipped = !exercise.isGraded
                onFinish(ExerciseResult(success: skipped, mistakes: model.totalMistakes,
                                        detail: skipped ? nil : "Đã bỏ qua – bài này sẽ được làm lại sau."))
            } label: {
                Text(exercise.isGraded ? "Bỏ qua" : "Tiếp tục")
            }
            .buttonStyle(DuoButtonStyle(color: .white, textColor: .duoGrayDark, height: 46, fullWidth: false))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.duoGray, lineWidth: 2).padding(.bottom, 4))
            .disabled(!isActive || model.finished)
            Spacer()
        }
    }
}
