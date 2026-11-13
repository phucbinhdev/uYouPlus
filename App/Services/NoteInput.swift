import Combine
import Foundation
import PianoCore
import QuartzCore

/// Nguồn của một nốt: đàn thật (MIDI) hay bàn phím trên màn hình.
enum InputSource {
    case midi
    case touch
}

struct NoteEvent {
    let pitch: Pitch
    let isOn: Bool
    let velocity: Int
    /// Thời điểm theo CACurrentMediaTime().
    let time: Double
    let source: InputSource
}

/// Gom các nốt từ đàn (Bluetooth/USB MIDI) và bàn phím ảo về một chỗ.
final class NoteInput: ObservableObject {
    /// Các phím đang được giữ.
    @Published private(set) var held: Set<Int> = []
    /// Nốt gần nhất (để hiển thị kiểm tra kết nối).
    @Published private(set) var lastEvent: NoteEvent?
    @Published private(set) var sustain = false

    let events = PassthroughSubject<NoteEvent, Never>()

    weak var synth: SynthEngine?
    /// Có phát âm thanh trên iPad cho nốt từ đàn thật không.
    var soundForMIDI: () -> Bool = { false }
    /// Đếm số nốt đã chơi.
    private(set) var notesPlayed = 0

    /// Gọi trên luồng chính.
    func send(_ event: NoteEvent) {
        if event.isOn {
            held.insert(event.pitch.midi)
            notesPlayed += 1
        } else {
            held.remove(event.pitch.midi)
        }
        if event.source == .touch || soundForMIDI() {
            if event.isOn {
                synth?.noteOn(event.pitch.midi, velocity: event.velocity)
            } else {
                synth?.noteOff(event.pitch.midi)
            }
        }
        if event.isOn { lastEvent = event }
        events.send(event)
    }

    func touchDown(_ midi: Int) {
        send(NoteEvent(pitch: Pitch(midi), isOn: true, velocity: 90, time: CACurrentMediaTime(), source: .touch))
    }

    func touchUp(_ midi: Int) {
        send(NoteEvent(pitch: Pitch(midi), isOn: false, velocity: 0, time: CACurrentMediaTime(), source: .touch))
    }

    func setSustain(_ on: Bool) {
        if sustain != on { sustain = on }
    }

    /// Thả mọi phím (ví dụ khi đàn bị ngắt kết nối).
    func releaseAll(source: InputSource) {
        for midi in held {
            send(NoteEvent(pitch: Pitch(midi), isOn: false, velocity: 0, time: CACurrentMediaTime(), source: source))
        }
    }

    func takeNotesPlayed() -> Int {
        defer { notesPlayed = 0 }
        return notesPlayed
    }
}
