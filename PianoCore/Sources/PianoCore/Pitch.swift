import Foundation

/// Cách hiển thị tên nốt.
public enum NoteNaming: String, Codable, CaseIterable, Identifiable {
    /// Đô Rê Mi Fa Sol La Si
    case solfege
    /// C D E F G A B
    case letter
    /// Đô (C)
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .solfege: return "Đô Rê Mi"
        case .letter: return "C D E"
        case .both: return "Đô (C)"
        }
    }
}

/// Khóa nhạc.
public enum Clef: String, Codable, CaseIterable {
    case treble
    case bass

    /// Bậc diatonic (xem `Pitch.diatonicStep`) của dòng kẻ dưới cùng.
    /// Khóa Sol: dòng dưới cùng là Mi4 (E4). Khóa Fa: Sol2 (G2).
    public var bottomLineStep: Int {
        switch self {
        case .treble: return 30 // E4
        case .bass: return 18 // G2
        }
    }

    public var displayName: String {
        switch self {
        case .treble: return "Khóa Sol"
        case .bass: return "Khóa Fa"
        }
    }

    /// Chọn khóa phù hợp cho một nhóm nốt.
    public static func best(for pitches: [Pitch]) -> Clef {
        guard !pitches.isEmpty else { return .treble }
        let below = pitches.filter { $0.midi < 60 }.count
        return below * 2 > pitches.count ? .bass : .treble
    }
}

public enum Accidental: String, Codable {
    case natural
    case sharp
    case flat

    public var symbol: String {
        switch self {
        case .natural: return ""
        case .sharp: return "♯"
        case .flat: return "♭"
        }
    }
}

/// Một cao độ (nốt nhạc) theo số MIDI. Đô giữa (C4) = 60.
///
/// Hai `Pitch` bằng nhau khi cùng số MIDI, cách viết (thăng/giáng) chỉ để hiển thị.
public struct Pitch: Codable, Comparable, CustomStringConvertible {
    public let midi: Int
    /// Ưu tiên viết dạng giáng (B♭ thay vì A♯) khi là phím đen.
    public let prefersFlat: Bool

    public init(_ midi: Int, prefersFlat: Bool = false) {
        self.midi = midi
        self.prefersFlat = prefersFlat
    }

    public static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    public static let solfegeNames = ["Đô", "Rê", "Mi", "Fa", "Sol", "La", "Si"]
    private static let naturalSemitones = [0, 2, 4, 5, 7, 9, 11]

    public static let middleC = Pitch(60)

    /// Tạo từ tên dạng "C4", "F#4", "Bb3", "Eb5".
    public init?(name raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard let first = name.first, let letterIdx = Pitch.letters.firstIndex(of: String(first).uppercased()) else {
            return nil
        }
        var rest = name.dropFirst()
        var shift = 0
        var flat = false
        while let c = rest.first, c == "#" || c == "♯" || c == "b" || c == "♭" {
            if c == "#" || c == "♯" { shift += 1 } else { shift -= 1; flat = true }
            rest = rest.dropFirst()
        }
        guard let octave = Int(rest) else { return nil }
        let midi = (octave + 1) * 12 + Pitch.naturalSemitones[letterIdx] + shift
        guard (0...127).contains(midi) else { return nil }
        self.init(midi, prefersFlat: flat)
    }

    public var pitchClass: Int { ((midi % 12) + 12) % 12 }
    public var octave: Int { Int((Double(midi) / 12).rounded(.down)) - 1 }
    public var isBlack: Bool { [1, 3, 6, 8, 10].contains(pitchClass) }
    public var frequency: Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// Chỉ số chữ cái (0 = C ... 6 = B) theo cách viết.
    public var letterIndex: Int {
        let sharpMap = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        let flatMap = [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6]
        return (isBlack && prefersFlat ? flatMap : sharpMap)[pitchClass]
    }

    public var accidental: Accidental {
        guard isBlack else { return .natural }
        return prefersFlat ? .flat : .sharp
    }

    /// Bậc diatonic tuyệt đối: C4 = 28, D4 = 29, E4 = 30 ...
    public var diatonicStep: Int { letterIndex + octave * 7 }

    /// Vị trí trên khuông: 0 = dòng dưới cùng, 1 = khe đầu tiên, 8 = dòng trên cùng.
    public func staffPosition(in clef: Clef) -> Int {
        diatonicStep - clef.bottomLineStep
    }

    public func letterName(withOctave: Bool = false) -> String {
        Pitch.letters[letterIndex] + accidental.symbol + (withOctave ? "\(octave)" : "")
    }

    public func solfegeName(withOctave: Bool = false) -> String {
        Pitch.solfegeNames[letterIndex] + accidental.symbol + (withOctave ? "\(octave)" : "")
    }

    public func name(_ naming: NoteNaming, withOctave: Bool = false) -> String {
        switch naming {
        case .solfege: return solfegeName(withOctave: withOctave)
        case .letter: return letterName(withOctave: withOctave)
        case .both: return "\(solfegeName(withOctave: withOctave)) (\(letterName(withOctave: withOctave)))"
        }
    }

    /// Tên ngắn gọn để in trong đầu nốt.
    public func shortName(_ naming: NoteNaming) -> String {
        naming == .letter ? letterName() : solfegeName()
    }

    public var description: String { letterName(withOctave: true) }

    public func transposed(_ semitones: Int) -> Pitch { Pitch(midi + semitones, prefersFlat: prefersFlat) }

    public func matches(_ other: Pitch, mode: MatchMode) -> Bool {
        switch mode {
        case .exact: return midi == other.midi
        case .pitchClass: return pitchClass == other.pitchClass
        }
    }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }
}

extension Pitch: Hashable {
    public static func == (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi == rhs.midi }
    public func hash(into hasher: inout Hasher) { hasher.combine(midi) }
}

/// Cách so khớp nốt người chơi đánh với nốt yêu cầu.
public enum MatchMode: String, Codable {
    /// Đúng phím (đúng quãng tám).
    case exact
    /// Đúng tên nốt, quãng tám nào cũng được.
    case pitchClass
}

/// Viết tắt tiện lợi: `P("C4")`.
public func P(_ name: String) -> Pitch {
    guard let p = Pitch(name: name) else { preconditionFailure("Tên nốt không hợp lệ: \(name)") }
    return p
}

/// Khoảng phím nên hiển thị trên bàn phím ảo cho một nhóm nốt: luôn bắt đầu ở Đô,
/// kết thúc ở Đô và dài ít nhất 2 quãng tám.
public func keyboardRange(for pitches: [Pitch], minimumOctaves: Int = 2) -> ClosedRange<Int> {
    guard let lo = pitches.map(\.midi).min(), let hi = pitches.map(\.midi).max() else {
        return 48...72
    }
    var low = (lo / 12) * 12
    var high = (hi / 12) * 12 + 12
    while high - low < minimumOctaves * 12 {
        // mở rộng về phía gần Đô giữa nhất
        if 60 - low > high - 60 { high += 12 } else { low -= 12 }
    }
    return max(21, low)...min(108, high)
}
