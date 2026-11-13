import Foundation

/// Một nốt (hoặc hợp âm, hoặc dấu lặng) trong bản nhạc.
public struct ScoreNote: Hashable, Codable {
    /// Rỗng = dấu lặng.
    public var pitches: [Pitch]
    /// Thời điểm bắt đầu, tính bằng phách (nốt đen = 1).
    public var beat: Double
    /// Trường độ, tính bằng phách.
    public var duration: Double
    /// Ngón tay gợi ý (1 = ngón cái ... 5 = ngón út).
    public var finger: Int?

    public init(pitches: [Pitch], beat: Double, duration: Double, finger: Int? = nil) {
        self.pitches = pitches
        self.beat = beat
        self.duration = duration
        self.finger = finger
    }

    public var isRest: Bool { pitches.isEmpty }
    public var endBeat: Double { beat + duration }
}

public enum ScoreParseError: Error, CustomStringConvertible, Equatable {
    case invalidToken(String)

    public var description: String {
        switch self {
        case .invalidToken(let t): return "Ký hiệu không hợp lệ: \(t)"
        }
    }
}

/// Đọc bản nhạc dạng chữ đơn giản.
///
/// Cú pháp mỗi ký hiệu (cách nhau bởi khoảng trắng, `|` là vạch nhịp và bị bỏ qua):
///  - `C4` nốt đen (mặc định), `C4:h` nốt trắng, `C4:w` nốt tròn, `C4:e` móc đơn, `C4:s` móc kép
///  - thêm `.` để có dấu chấm dôi: `C4:q.`; hoặc số phách: `C4:1.5`
///  - hợp âm: `C4+E4+G4:w`
///  - ngón tay: `C4:q@1`
///  - dấu lặng: `R:q`
public enum ScoreParser {
    public static func parse(_ text: String, startBeat: Double = 0) throws -> [ScoreNote] {
        var result: [ScoreNote] = []
        var beat = startBeat
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "|" })
        for raw in tokens {
            let token = String(raw)
            var body = token
            var finger: Int?
            if let at = body.firstIndex(of: "@") {
                guard let f = Int(body[body.index(after: at)...]), (1...5).contains(f) else {
                    throw ScoreParseError.invalidToken(token)
                }
                finger = f
                body = String(body[..<at])
            }
            var durationText = "q"
            if let colon = body.firstIndex(of: ":") {
                durationText = String(body[body.index(after: colon)...])
                body = String(body[..<colon])
            }
            guard let duration = parseDuration(durationText) else { throw ScoreParseError.invalidToken(token) }
            var pitches: [Pitch] = []
            if body.uppercased() != "R" {
                for part in body.split(separator: "+") {
                    guard let p = Pitch(name: String(part)) else { throw ScoreParseError.invalidToken(token) }
                    pitches.append(p)
                }
                if pitches.isEmpty { throw ScoreParseError.invalidToken(token) }
            }
            result.append(ScoreNote(pitches: pitches, beat: beat, duration: duration, finger: finger))
            beat += duration
        }
        return result
    }

    static func parseDuration(_ text: String) -> Double? {
        if let n = Double(text), n > 0 { return n }
        var t = Substring(text)
        var dotted = false
        if t.hasSuffix(".") { dotted = true; t = t.dropLast() }
        let base: Double
        switch t {
        case "w": base = 4
        case "h": base = 2
        case "q": base = 1
        case "e": base = 0.5
        case "s": base = 0.25
        default: return nil
        }
        return dotted ? base * 1.5 : base
    }
}

/// Bài hát / bản nhạc đầy đủ.
public struct Song: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// 1 = dễ, 2 = trung bình, 3 = khó
    public let level: Int
    /// Số phách (nốt đen) mỗi phút.
    public let tempo: Double
    /// Số phách (tính theo nốt đen) trong một ô nhịp. 3/4 = 3, 6/8 = 3, 3/8 = 1.5
    public let beatsPerMeasure: Double
    /// Độ dài ô nhịp lấy đà ở đầu bài (tính bằng phách).
    public let pickup: Double
    public let clef: Clef
    public let notes: [ScoreNote]

    public init(id: String, title: String, subtitle: String, level: Int, tempo: Double,
                beatsPerMeasure: Double = 4, pickup: Double = 0, clef: Clef? = nil, score: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.level = level
        self.tempo = tempo
        self.beatsPerMeasure = beatsPerMeasure
        self.pickup = pickup
        do {
            self.notes = try ScoreParser.parse(score)
        } catch {
            preconditionFailure("Bài \(id): \(error)")
        }
        self.clef = clef ?? Clef.best(for: notes.flatMap(\.pitches))
    }

    public var playableNotes: [ScoreNote] { notes.filter { !$0.isRest } }
    public var totalBeats: Double { notes.last?.endBeat ?? 0 }
    public var allPitches: [Pitch] { notes.flatMap(\.pitches) }
    public var secondsPerBeat: Double { 60 / tempo }
    public var durationSeconds: Double { totalBeats * secondsPerBeat }

    /// Vị trí (phách) các vạch nhịp.
    public var barlineBeats: [Double] {
        var result: [Double] = []
        var b = pickup > 0 ? pickup : beatsPerMeasure
        while b < totalBeats - 0.001 {
            result.append(b)
            b += beatsPerMeasure
        }
        return result
    }

    public static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
