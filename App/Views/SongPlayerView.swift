import Combine
import PianoCore
import QuartzCore
import SwiftUI

final class SongPlayerModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case wait = "Chờ"
        case tempo = "Theo nhịp"
        var id: String { rawValue }
    }

    enum Phase: Equatable { case ready, demo, countIn, playing, finished }

    let song: Song
    let strictOctave: Bool
    @Published var mode: Mode = .wait
    @Published var tempoScale: Double = 0.8
    @Published var metronome = true
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var noteColors: [Int: Color] = [:]
    @Published private(set) var keyColors: [Int: Color] = [:]
    @Published private(set) var hintMidis: [Int] = []
    @Published private(set) var waitNoteIndex: Int?
    @Published private(set) var result: TimedResult?
    @Published private(set) var lastGrade: TimingGrade?
    @Published private(set) var stepsDone = 0

    private var evaluator: StepEvaluator?
    private var tracker: TimedNoteTracker?
    private let playable: [Int]
    private var stepMistakes: Set<Int> = []
    private(set) var beatZero: Double = 0
    private var timer: AnyCancellable?
    private var startDate = Date()

    init(song: Song, strictOctave: Bool) {
        self.song = song
        self.strictOctave = strictOctave
        playable = song.notes.enumerated().filter { !$0.element.isRest }.map(\.offset)
    }

    var spb: Double { 60 / (song.tempo * tempoScale) }
    var totalSteps: Int { playable.count }
    var duration: TimeInterval { Date().timeIntervalSince(startDate) }
    var isRunning: Bool { phase == .countIn || phase == .playing || phase == .demo }
    private var matchMode: MatchMode { strictOctave ? .exact : .pitchClass }

    /// Phách hiện tại (để cuộn bản nhạc).
    func currentBeat(at time: Double) -> Double {
        if mode == .wait && phase != .demo {
            if let i = waitNoteIndex { return song.notes[i].beat }
            return phase == .finished ? song.totalBeats : 0
        }
        guard isRunning else { return phase == .finished ? song.totalBeats : 0 }
        return (time - beatZero) / spb
    }

    func start(synth: SynthEngine) {
        reset(synth: synth)
        startDate = Date()
        switch mode {
        case .wait:
            evaluator = StepEvaluator(steps: playable.map { song.notes[$0].pitches }, mode: matchMode)
            phase = .playing
            waitNoteIndex = playable.first
            updateWaitHints()
        case .tempo:
            tracker = TimedNoteTracker(notes: song.notes, secondsPerBeat: spb, mode: matchMode)
            let countIn = max(2, Int(ceil(song.beatsPerMeasure)))
            let now = CACurrentMediaTime() + 0.3
            beatZero = now + Double(countIn) * spb
            let beats = Int(ceil(song.totalBeats))
            for i in 0..<(countIn + (metronome ? beats : 0)) {
                let b = i - countIn
                let accent = b < 0 ? i == 0 : (Double(b) - song.pickup).truncatingRemainder(dividingBy: song.beatsPerMeasure) == 0
                synth.click(at: now + Double(i) * spb, accent: accent)
            }
            phase = .countIn
            startTimer(synth: synth)
        }
    }

    func demo(synth: SynthEngine) {
        reset(synth: synth)
        beatZero = CACurrentMediaTime() + 0.4
        let items = song.notes.filter { !$0.isRest }.map { n in
            (midi: n.pitches.map(\.midi), start: n.beat * spb, duration: n.duration * spb)
        }
        synth.schedule(notes: items, startTime: beatZero)
        phase = .demo
        startTimer(synth: synth)
    }

    func stop(synth: SynthEngine) {
        reset(synth: synth)
    }

    private func reset(synth: SynthEngine) {
        synth.stopAll()
        timer = nil
        evaluator = nil
        tracker = nil
        noteColors = [:]
        keyColors = [:]
        hintMidis = []
        waitNoteIndex = nil
        result = nil
        lastGrade = nil
        stepMistakes = []
        stepsDone = 0
        phase = .ready
    }

    private func startTimer(synth: SynthEngine) {
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let beat = (now - beatZero) / spb
        if phase == .countIn && beat >= -0.25 { phase = .playing }
        if phase == .demo {
            let idx = song.notes.lastIndex { !$0.isRest && $0.beat <= beat + 0.05 }
            let hints = idx.map { song.notes[$0].endBeat > beat ? song.notes[$0].pitches.map(\.midi) : [] } ?? []
            if hints != hintMidis { hintMidis = hints }
            if beat > song.totalBeats + 0.5 {
                timer = nil
                phase = .ready
                hintMidis = []
            }
            return
        }
        guard let tracker = tracker else { return }
        for i in tracker.expire(before: now - beatZero) {
            noteColors[tracker.targets[i].noteIndex] = .duoRed
        }
        // Gợi ý phím cho nốt sắp tới.
        let upcoming = tracker.targets.first { $0.grade == nil }
        var hints: [Int] = []
        if let u = upcoming, u.time - (now - beatZero) < spb * 1.2 {
            hints = tracker.targets.filter { $0.grade == nil && abs($0.time - u.time) < 0.001 }.compactMap { $0.pitch?.midi }
        }
        if hints != hintMidis { hintMidis = hints }
        if beat > song.totalBeats + 1 {
            finish(tracker.finish())
        }
    }

    func handle(_ e: NoteEvent) {
        if !e.isOn {
            evaluator?.noteOff(e.pitch)
            keyColors[e.pitch.midi] = nil
            return
        }
        switch mode {
        case .wait:
            guard phase == .playing, let ev = evaluator, let fb = ev.noteOn(e.pitch) else { return }
            keyColors[e.pitch.midi] = fb.isCorrect ? .duoGreen : .duoRed
            if !fb.isCorrect {
                stepMistakes.insert(ev.stepIndex)
                if let idx = waitNoteIndex { noteColors[idx] = .duoOrange }
            }
            if let done = fb.completedStep {
                noteColors[playable[done]] = stepMistakes.contains(done) ? Color(hex: "89E219") : .duoGreen
                stepsDone = done + 1
                waitNoteIndex = ev.stepIndex < playable.count ? playable[ev.stepIndex] : nil
                updateWaitHints()
            }
            if fb.outcome != nil {
                let clean = playable.count - stepMistakes.count
                finish(TimedResult(perfect: clean, good: stepMistakes.count, miss: 0, wrong: ev.mistakes))
            }
        case .tempo:
            guard phase == .playing || phase == .countIn, let tracker = tracker else { return }
            if let hit = tracker.noteOn(e.pitch, at: e.time - beatZero) {
                let idx = tracker.targets[hit.target].noteIndex
                noteColors[idx] = hit.grade == .perfect ? .duoGreen : Color(hex: "89E219")
                keyColors[e.pitch.midi] = .duoGreen
                lastGrade = hit.grade
            } else {
                keyColors[e.pitch.midi] = .duoRed
                lastGrade = .miss
            }
        }
    }

    private func updateWaitHints() {
        hintMidis = evaluator?.remainingInStep.map(\.midi) ?? []
    }

    private func finish(_ r: TimedResult) {
        timer = nil
        hintMidis = []
        waitNoteIndex = nil
        result = r
        phase = .finished
    }
}

struct SongPlayerView: View {
    let song: Song
    var onClose: () -> Void

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var input: NoteInput
    @EnvironmentObject private var synth: SynthEngine
    @StateObject private var model: SongPlayerModel
    @State private var xpEarned = 0

    init(song: Song, strictOctave: Bool, onClose: @escaping () -> Void) {
        self.song = song
        self.onClose = onClose
        _model = StateObject(wrappedValue: SongPlayerModel(song: song, strictOctave: strictOctave))
    }

    /// Số khe khuông cho mỗi phách.
    private var beatWidth: CGFloat {
        let shortest = song.notes.map(\.duration).min() ?? 1
        return max(3.4, 1.7 / CGFloat(shortest))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                topBar
                staff
                    .frame(height: min(300, max(190, geo.size.height * 0.36)))
                    .card(padding: 6)
                    .padding(.horizontal, 16)
                controls
                Spacer(minLength: 0)
                PianoKeyboardView(
                    range: keyboardRange(for: song.allPitches),
                    pressed: input.held,
                    keyColors: model.keyColors,
                    hints: Dictionary(uniqueKeysWithValues: model.hintMidis.map { ($0, Color.duoBlue) }),
                    naming: app.settings.naming,
                    labelAllKeys: app.settings.showKeyLabels,
                    onNoteOn: { input.touchDown($0) },
                    onNoteOff: { input.touchUp($0) }
                )
                .frame(height: min(260, max(160, geo.size.height * 0.3)))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .overlay(resultOverlay)
        .onReceive(input.events) { model.handle($0) }
        .onChange(of: model.result) { r in
            guard let r = r else { return }
            xpEarned = app.recordSong(song, result: r, duration: model.duration)
            if app.settings.soundEffects { synth.playEffect(r.stars > 0 ? .complete : .fail) }
        }
        .onDisappear { model.stop(synth: synth) }
    }

    // MARK: Thanh trên

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                model.stop(synth: synth)
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.duoGrayDark)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.rounded(22, .heavy)).foregroundColor(.duoText).lineLimit(1)
                Text(song.subtitle).font(.rounded(14, .semibold)).foregroundColor(.duoSubtext).lineLimit(1)
            }
            Spacer()
            Picker("Chế độ", selection: $model.mode) {
                ForEach(SongPlayerModel.Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(model.isRunning)
            ConnectionDot()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Khuông nhạc cuộn

    private var staff: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !(model.isRunning && (model.mode == .tempo || model.phase == .demo)))) { _ in
            let beat = model.currentBeat(at: CACurrentMediaTime())
            let lead: CGFloat = 5
            let x = CGFloat(beat) * beatWidth
            StaffView(clef: song.clef,
                      notes: staffNotes,
                      barlines: song.barlineBeats.map { CGFloat($0) * beatWidth - 1.2 },
                      scroll: max(0, x - lead),
                      playhead: (model.mode == .tempo || model.phase == .demo) && model.isRunning ? x : nil,
                      showLabels: app.settings.showNoteNames)
                .animation(model.mode == .wait ? .easeInOut(duration: 0.25) : nil, value: model.waitNoteIndex)
                .overlay(countIn(beat: beat), alignment: .topTrailing)
        }
    }

    private var staffNotes: [StaffNote] {
        song.notes.enumerated().map { i, n in
            StaffNote(id: i, x: CGFloat(n.beat) * beatWidth, pitches: n.pitches, duration: n.duration,
                      color: model.noteColors[i] ?? (n.isRest ? .duoGrayDark : (i == model.waitNoteIndex ? .duoBlue : .duoText)),
                      label: n.isRest ? nil : n.pitches.map { $0.shortName(app.settings.naming) }.joined(separator: "·"),
                      finger: app.settings.showFingers ? n.finger : nil,
                      highlight: i == model.waitNoteIndex)
        }
    }

    @ViewBuilder private func countIn(beat: Double) -> some View {
        if model.phase == .countIn {
            Text("\(max(1, Int(ceil(-beat))))")
                .font(.rounded(56, .heavy))
                .foregroundColor(.duoOrange)
                .padding(16)
        } else if model.mode == .tempo, model.phase == .playing, let g = model.lastGrade {
            Text(gradeText(g))
                .font(.rounded(26, .heavy))
                .foregroundColor(gradeColor(g))
                .padding(16)
        }
    }

    private func gradeText(_ g: TimingGrade) -> String {
        switch g {
        case .perfect: return "Tuyệt!"
        case .good: return "Tốt"
        case .miss: return "Trượt"
        }
    }

    private func gradeColor(_ g: TimingGrade) -> Color {
        switch g {
        case .perfect: return .duoGreen
        case .good: return Color(hex: "89E219")
        case .miss: return .duoRed
        }
    }

    // MARK: Điều khiển

    private var controls: some View {
        HStack(spacing: 14) {
            if model.isRunning {
                Button {
                    model.stop(synth: synth)
                } label: {
                    Label("Dừng", systemImage: "stop.fill")
                }
                .buttonStyle(DuoButtonStyle(color: .duoRed, height: 50, fullWidth: false))
            } else {
                Button {
                    model.start(synth: synth)
                } label: {
                    Label(model.phase == .finished ? "Chơi lại" : "Bắt đầu", systemImage: "play.fill")
                }
                .buttonStyle(DuoButtonStyle(color: .duoGreen, height: 50, fullWidth: false))
                Button {
                    model.demo(synth: synth)
                } label: {
                    Label("Nghe mẫu", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 50, fullWidth: false))
            }
            Spacer()
            if model.mode == .wait && model.phase == .playing {
                Text("\(model.stepsDone)/\(model.totalSteps) nốt")
                    .font(.rounded(18, .heavy))
                    .foregroundColor(.duoSubtext)
            }
            HStack(spacing: 8) {
                Image(systemName: "tortoise.fill").foregroundColor(.duoGrayDark)
                Slider(value: $model.tempoScale, in: 0.4...1.2, step: 0.05)
                    .frame(width: 150)
                    .disabled(model.isRunning)
                Image(systemName: "hare.fill").foregroundColor(.duoGrayDark)
                Text("\(Int(song.tempo * model.tempoScale)) BPM")
                    .font(.rounded(15, .bold))
                    .foregroundColor(.duoSubtext)
                    .frame(width: 76, alignment: .leading)
            }
            if model.mode == .tempo {
                Toggle(isOn: $model.metronome) {
                    Image(systemName: "metronome.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .duoOrange))
                .frame(width: 90)
                .disabled(model.isRunning)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Kết quả

    @ViewBuilder private var resultOverlay: some View {
        if let r = model.result, model.phase == .finished {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 18) {
                    MascotView(mood: r.stars >= 2 ? .excited : (r.stars == 1 ? .happy : .sad), size: 110)
                    Text(r.stars >= 3 ? "Xuất sắc!" : (r.stars >= 1 ? "Làm tốt lắm!" : "Cố lên nhé!"))
                        .font(.rounded(32, .heavy))
                        .foregroundColor(.duoText)
                    HStack(spacing: 10) {
                        ForEach(0..<3) { i in
                            Image(systemName: i < r.stars ? "star.fill" : "star")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(i < r.stars ? .duoYellow : .duoGray)
                        }
                    }
                    HStack(spacing: 12) {
                        StatTile(title: "Điểm", value: "\(Int((r.score * 100).rounded()))%", color: .duoGreen, icon: "scope")
                        StatTile(title: "XP", value: "+\(xpEarned)", color: .duoYellow, icon: "bolt.fill")
                    }
                    Text(detailText(r))
                        .font(.rounded(16, .semibold))
                        .foregroundColor(.duoSubtext)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 14) {
                        Button("Chơi lại") { model.start(synth: synth) }
                            .buttonStyle(DuoButtonStyle(color: .duoBlue))
                        Button("Xong") {
                            model.stop(synth: synth)
                            onClose()
                        }
                        .buttonStyle(DuoButtonStyle(color: .duoGreen))
                    }
                }
                .padding(28)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    private func detailText(_ r: TimedResult) -> String {
        if model.mode == .wait {
            return "Đánh đúng ngay lần đầu \(r.perfect)/\(r.total) nốt • bấm sai \(r.wrong) lần"
        }
        return "Tuyệt: \(r.perfect) • Tốt: \(r.good) • Trượt: \(r.miss) • Sai nốt: \(r.wrong)"
    }
}
