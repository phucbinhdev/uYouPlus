import Combine
import PianoCore
import QuartzCore
import SwiftUI

final class RhythmModel: ObservableObject {
    enum Phase: Equatable { case ready, demo, countIn, playing, done }

    let pattern: RhythmPattern
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var grades: [Int: TimingGrade] = [:]
    @Published private(set) var lastTap: TimingGrade?
    private(set) var tracker: TimedNoteTracker
    /// Thời điểm phách 0 (CACurrentMediaTime).
    private(set) var beatZero: Double = 0
    private var timer: AnyCancellable?

    init(pattern: RhythmPattern) {
        self.pattern = pattern
        tracker = TimedNoteTracker(rhythm: pattern)
    }

    var spb: Double { pattern.secondsPerBeat }

    func currentBeat(at time: Double) -> Double {
        (time - beatZero) / spb
    }

    func start(synth: SynthEngine, demo: Bool, onDone: @escaping (TimedResult?) -> Void) {
        synth.stopAll()
        tracker = TimedNoteTracker(rhythm: pattern)
        grades = [:]
        lastTap = nil
        let now = CACurrentMediaTime() + 0.25
        let countIn = Double(pattern.countInBeats)
        beatZero = now + countIn * spb
        let totalBeats = Int(ceil(pattern.totalBeats))
        // Tiếng gõ nhịp: đếm vào + suốt bài.
        for i in 0..<(pattern.countInBeats + totalBeats) {
            let beatIndex = i - pattern.countInBeats
            let accent = beatIndex >= 0 ? (Double(beatIndex).truncatingRemainder(dividingBy: pattern.beatsPerMeasure) == 0) : i == 0
            synth.click(at: now + Double(i) * spb, accent: accent)
        }
        if demo {
            let items = pattern.notes.filter { !$0.isRest }.map { n in
                (midi: [72], start: n.beat * spb, duration: n.duration * spb * 0.9)
            }
            synth.schedule(notes: items, startTime: beatZero)
        }
        phase = demo ? .demo : .countIn
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick(demo: demo, onDone: onDone)
        }
    }

    private func tick(demo: Bool, onDone: (TimedResult?) -> Void) {
        let now = CACurrentMediaTime()
        let beat = currentBeat(at: now)
        if !demo {
            if phase == .countIn && beat >= -0.3 { phase = .playing }
            for i in tracker.expire(before: now - beatZero) {
                grades[tracker.targets[i].noteIndex] = .miss
            }
        }
        if beat > pattern.totalBeats + 0.5 {
            timer = nil
            if demo {
                phase = .ready
                onDone(nil)
            } else {
                phase = .done
                onDone(tracker.finish())
            }
        }
    }

    func tap(at time: Double) {
        guard phase == .playing || phase == .countIn else { return }
        if let hit = tracker.noteOn(Pitch.middleC, at: time - beatZero) {
            grades[tracker.targets[hit.target].noteIndex] = hit.grade
            lastTap = hit.grade
        } else {
            lastTap = .miss
        }
    }

    func cancel() {
        timer = nil
    }
}

/// Bài tập gõ theo tiết tấu.
struct RhythmExerciseView: View {
    let pattern: RhythmPattern
    let isActive: Bool
    let onFinish: (ExerciseResult) -> Void

    @EnvironmentObject private var input: NoteInput
    @EnvironmentObject private var synth: SynthEngine
    @StateObject private var model: RhythmModel

    init(pattern: RhythmPattern, isActive: Bool, onFinish: @escaping (ExerciseResult) -> Void) {
        self.pattern = pattern
        self.isActive = isActive
        self.onFinish = onFinish
        _model = StateObject(wrappedValue: RhythmModel(pattern: pattern))
    }

    private let beatWidth: CGFloat = 3.4

    var body: some View {
        VStack(spacing: 18) {
            Text("Gõ theo tiết tấu")
                .font(.rounded(28, .heavy))
                .foregroundColor(.duoText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            Text(instruction)
                .font(.rounded(18, .semibold))
                .foregroundColor(.duoSubtext)
                .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.animation(minimumInterval: nil, paused: model.phase == .ready || model.phase == .done)) { tl in
                let now = CACurrentMediaTime()
                let beat = model.phase == .ready ? -1 : model.currentBeat(at: now)
                StaffView(clef: .treble,
                          notes: staffNotes,
                          barlines: barlines,
                          playhead: beat >= -0.2 ? CGFloat(beat) * beatWidth : nil,
                          showLabels: false)
                    .overlay(countInOverlay(beat: beat), alignment: .topTrailing)
                    .accessibilityHidden(tl.date == .distantFuture)
            }
            .frame(maxHeight: 240)
            .card(padding: 8)

            HStack(spacing: 18) {
                Button {
                    model.start(synth: synth, demo: true) { _ in }
                } label: {
                    Label("Nghe mẫu", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 50, fullWidth: false))
                .disabled(model.phase != .ready || !isActive)

                Button {
                    model.start(synth: synth, demo: false) { result in
                        guard let r = result else { return }
                        let o = r.outcome
                        onFinish(ExerciseResult(success: o.success, mistakes: r.miss + r.wrong,
                                                detail: "Đúng nhịp \(r.perfect + r.good)/\(r.total) nốt" + (r.wrong > 0 ? ", gõ thừa \(r.wrong) lần" : "") + "."))
                    }
                } label: {
                    Label("Bắt đầu", systemImage: "play.fill")
                }
                .buttonStyle(DuoButtonStyle(color: .duoGreen, height: 50, fullWidth: false))
                .disabled(model.phase != .ready || !isActive)
            }

            Spacer(minLength: 0)

            // Vùng gõ cho người không dùng đàn.
            Button {
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 40, weight: .bold))
                    Text("Chạm vào đây hoặc nhấn phím bất kỳ trên đàn")
                        .font(.rounded(17, .heavy))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(RoundedRectangle(cornerRadius: 22).fill(tapColor))
            }
            .buttonStyle(TapPadStyle { model.tap(at: CACurrentMediaTime()) })
            .disabled(!isActive)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 28)
        .onReceive(input.events) { e in
            guard e.isOn, isActive else { return }
            model.tap(at: e.time)
        }
        .onDisappear { model.cancel() }
    }

    private var instruction: String {
        switch model.phase {
        case .ready: return "Bấm “Bắt đầu”, nghe 4 tiếng đếm rồi gõ (nhấn phím bất kỳ) đúng lúc vạch xanh chạm vào nốt."
        case .demo: return "Đang phát mẫu…"
        case .countIn: return "Chuẩn bị… 1, 2, 3, 4"
        case .playing: return "Gõ đúng nhịp!"
        case .done: return "Xong!"
        }
    }

    private var tapColor: Color {
        switch model.lastTap {
        case .perfect: return .duoGreen
        case .good: return Color(hex: "89E219")
        case .miss: return .duoOrange
        case nil: return .duoPurple
        }
    }

    private var staffNotes: [StaffNote] {
        pattern.notes.enumerated().map { i, n in
            var color = Color.duoText
            switch model.grades[i] {
            case .perfect: color = .duoGreen
            case .good: color = Color(hex: "89E219")
            case .miss: color = .duoRed
            case nil: break
            }
            return StaffNote(id: i, x: CGFloat(n.beat) * beatWidth, pitches: n.isRest ? [] : [P("B4")],
                             duration: n.duration, color: color)
        }
    }

    private var barlines: [CGFloat] {
        var result: [CGFloat] = []
        var b = pattern.beatsPerMeasure
        while b < pattern.totalBeats - 0.01 {
            result.append(CGFloat(b) * beatWidth - 1)
            b += pattern.beatsPerMeasure
        }
        return result
    }

    @ViewBuilder private func countInOverlay(beat: Double) -> some View {
        if model.phase == .countIn || (model.phase == .demo && beat < 0) {
            let n = Int(floor(beat + Double(pattern.countInBeats))) + 1
            if n >= 1 && n <= pattern.countInBeats {
                Text("\(n)")
                    .font(.rounded(54, .heavy))
                    .foregroundColor(.duoOrange)
                    .padding(16)
            }
        }
    }
}

/// Kiểu nút gọi hành động ngay khi chạm xuống (không đợi nhấc tay) để chấm nhịp chính xác.
struct TapPadStyle: ButtonStyle {
    var onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { onPress() }
            }
    }
}
