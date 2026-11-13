import Combine
import PianoCore
import QuartzCore
import SwiftUI

/// Máy đếm nhịp đơn giản dùng bộ tổng hợp âm thanh.
final class Metronome: ObservableObject {
    @Published var bpm: Double = 80
    @Published var beatsPerBar = 4
    @Published private(set) var isOn = false
    @Published private(set) var beat = 0
    private var nextTime: Double = 0
    private var count = 0
    private var timer: AnyCancellable?

    func toggle(synth: SynthEngine) {
        isOn ? stop() : start(synth: synth)
    }

    func start(synth: SynthEngine) {
        isOn = true
        count = 0
        nextTime = CACurrentMediaTime() + 0.1
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self, weak synth] _ in
            guard let self = self, let synth = synth else { return }
            let now = CACurrentMediaTime()
            while self.nextTime < now + 0.25 {
                synth.click(at: self.nextTime, accent: self.count % self.beatsPerBar == 0)
                let b = self.count % self.beatsPerBar
                let delay = max(0, self.nextTime - now)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.beat = b }
                self.count += 1
                self.nextTime += 60 / self.bpm
            }
        }
    }

    func stop() {
        isOn = false
        timer = nil
    }
}

struct FreePlayView: View {
    @Binding var showConnect: Bool
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var input: NoteInput
    @EnvironmentObject private var synth: SynthEngine
    @StateObject private var metronome = Metronome()
    @State private var lowC = 48
    @State private var octaves = 3
    @State private var history: [Pitch] = []
    @State private var appearDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(showConnect: $showConnect)
            GeometryReader { geo in
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        chordCard
                        historyCard
                    }
                    .frame(maxHeight: .infinity)
                    toolbar
                    PianoKeyboardView(range: lowC...(lowC + octaves * 12), pressed: input.held,
                                      naming: app.settings.naming, labelAllKeys: app.settings.showKeyLabels,
                                      onNoteOn: { input.touchDown($0) }, onNoteOff: { input.touchUp($0) })
                        .frame(height: min(300, max(180, geo.size.height * 0.42)))
                }
                .padding(16)
            }
        }
        .background(Color.duoPanel.ignoresSafeArea())
        .onReceive(input.events) { e in
            guard e.isOn else { return }
            history.append(e.pitch)
            if history.count > 16 { history.removeFirst(history.count - 16) }
            // Tự cuộn bàn phím ảo tới vùng đang chơi trên đàn thật.
            if e.source == .midi && !(lowC...(lowC + octaves * 12)).contains(e.pitch.midi) {
                lowC = max(24, min(96 - octaves * 12, (e.pitch.midi / 12) * 12 - 12))
            }
        }
        .onAppear { appearDate = Date() }
        .onDisappear {
            metronome.stop()
            app.addPracticeTime(Date().timeIntervalSince(appearDate), notes: 0)
        }
    }

    private var chordCard: some View {
        let chord = ChordDetector.detect(Array(input.held), naming: app.settings.naming)
        let heldNames = input.held.sorted().map { Pitch($0).name(app.settings.naming) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Hợp âm")
                .font(.rounded(16, .heavy))
                .foregroundColor(.duoGrayDark)
            if let c = chord {
                Text(c.symbol)
                    .font(.rounded(60, .heavy))
                    .foregroundColor(.duoPurple)
                Text(c.vietnameseName + (c.isInversion ? " (thể đảo)" : ""))
                    .font(.rounded(20, .bold))
                    .foregroundColor(.duoText)
            } else if input.held.count == 2, let lo = input.held.min(), let hi = input.held.max() {
                Text(ChordDetector.intervalName(hi - lo))
                    .font(.rounded(34, .heavy))
                    .foregroundColor(.duoBlue)
            } else if let only = input.held.first, input.held.count == 1 {
                Text(Pitch(only).name(app.settings.naming, withOctave: true))
                    .font(.rounded(52, .heavy))
                    .foregroundColor(.duoGreen)
            } else {
                Text("Hãy đánh vài nốt cùng lúc")
                    .font(.rounded(20, .bold))
                    .foregroundColor(.duoGray)
            }
            Spacer(minLength: 0)
            Text(heldNames.joined(separator: " · "))
                .font(.rounded(16, .bold))
                .foregroundColor(.duoSubtext)
                .lineLimit(2)
        }
        .frame(maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 18)
    }

    private var historyCard: some View {
        let recent = Array(history.suffix(12))
        let notes = recent.enumerated().map { i, p in
            StaffNote(id: i, x: CGFloat(i) * 3.4, pitches: [p], duration: 1,
                      color: i == recent.count - 1 ? .duoBlue : .duoText,
                      label: p.shortName(app.settings.naming))
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nốt vừa chơi")
                    .font(.rounded(16, .heavy))
                    .foregroundColor(.duoGrayDark)
                Spacer()
                Button("Xóa") { history.removeAll() }
                    .font(.rounded(15, .heavy))
                    .foregroundColor(.duoBlue)
            }
            StaffView(clef: Clef.best(for: recent), notes: notes, showLabels: app.settings.showNoteNames)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(padding: 14)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                lowC = max(24, lowC - 12)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 42, fullWidth: false))
            Text("Đô\(lowC / 12 - 1) – Đô\((lowC + octaves * 12) / 12 - 1)")
                .font(.rounded(16, .heavy))
                .foregroundColor(.duoText)
                .frame(minWidth: 110)
            Button {
                lowC = min(96 - octaves * 12, lowC + 12)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 42, fullWidth: false))
            Picker("Số quãng tám", selection: $octaves) {
                Text("2 quãng").tag(2)
                Text("3 quãng").tag(3)
                Text("4 quãng").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: octaves) { o in lowC = min(lowC, 96 - o * 12) }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    metronome.toggle(synth: synth)
                } label: {
                    Image(systemName: "metronome.fill")
                }
                .buttonStyle(DuoButtonStyle(color: metronome.isOn ? .duoOrange : .duoGrayDark, height: 42, fullWidth: false))
                Stepper("\(Int(metronome.bpm)) BPM", value: $metronome.bpm, in: 40...200, step: 5)
                    .font(.rounded(16, .heavy))
                    .frame(width: 190)
                if metronome.isOn {
                    HStack(spacing: 4) {
                        ForEach(0..<metronome.beatsPerBar, id: \.self) { i in
                            Circle()
                                .fill(i == metronome.beat ? Color.duoOrange : Color.duoGray)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
    }
}
