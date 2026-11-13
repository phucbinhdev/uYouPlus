import Foundation

/// Cách đề bài được hiển thị cho bài "tìm phím".
public enum PromptStyle: String, Codable {
    /// Chỉ hiện tên nốt.
    case name
    /// Chỉ hiện nốt trên khuông nhạc (bài tập đọc nốt).
    case staff
    /// Hiện cả tên và khuông nhạc.
    case nameAndStaff
}

/// Mẫu tiết tấu cho bài tập gõ nhịp.
public struct RhythmPattern: Hashable, Codable {
    /// Nốt (cao độ không quan trọng) và dấu lặng.
    public var notes: [ScoreNote]
    public var tempo: Double
    public var beatsPerMeasure: Double
    public var countInBeats: Int

    public init(score: String, tempo: Double = 80, beatsPerMeasure: Double = 4, countInBeats: Int = 4) {
        // Mọi nốt tiết tấu được hiển thị ở vị trí Đô5 (khe thứ ba khóa Sol) cho dễ nhìn.
        let parsed = (try? ScoreParser.parse(score)) ?? []
        self.notes = parsed
        self.tempo = tempo
        self.beatsPerMeasure = beatsPerMeasure
        self.countInBeats = countInBeats
    }

    public var onsets: [Double] { notes.filter { !$0.isRest }.map(\.beat) }
    public var totalBeats: Double { notes.last?.endBeat ?? 0 }
    public var secondsPerBeat: Double { 60 / tempo }
}

public enum ExerciseKind: Hashable {
    /// Giới thiệu nốt mới: hiển thị phím sáng, người học nhấn để tiếp tục. Không chấm điểm.
    case introduce(Pitch, tip: String)
    /// Nhấn đúng phím được yêu cầu.
    case findKey(Pitch, prompt: PromptStyle)
    /// Đọc nốt trên khuông và chọn tên đúng.
    case nameQuiz(Pitch, choices: [Pitch])
    /// Nghe một nốt rồi đánh lại.
    case earTraining(Pitch, range: [Pitch])
    /// Đánh một chuỗi nốt (giai điệu ngắn) theo chế độ chờ.
    case sequence(title: String, notes: [ScoreNote])
    /// Nhấn cùng lúc các nốt của hợp âm.
    case chord(name: String, pitches: [Pitch])
    /// Gõ theo tiết tấu (bấm phím bất kỳ).
    case rhythm(RhythmPattern)
    /// Câu hỏi lý thuyết trắc nghiệm.
    case theory(question: String, choices: [String], answer: Int, explanation: String?)
}

public struct Exercise: Identifiable, Hashable {
    public let id: UUID
    public let kind: ExerciseKind
    /// Bắt buộc đúng quãng tám, kể cả khi người học chọn chế độ dễ.
    public let requiresExactOctave: Bool
    /// Cho phép hiện phím gợi ý (tắt với bài luyện đọc nốt).
    public let showHints: Bool

    public init(_ kind: ExerciseKind, requiresExactOctave: Bool = false, showHints: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.requiresExactOctave = requiresExactOctave
        self.showHints = showHints
    }

    /// Bài giới thiệu không bị trừ tim.
    public var isGraded: Bool {
        if case .introduce = kind { return false }
        return true
    }

    /// Cần đàn (hoặc bàn phím ảo) để trả lời.
    public var usesKeyboard: Bool {
        switch kind {
        case .nameQuiz, .theory: return false
        default: return true
        }
    }

    public func matchMode(strictOctave: Bool) -> MatchMode {
        if requiresExactOctave { return .exact }
        if case .earTraining = kind { return .pitchClass }
        return strictOctave ? .exact : .pitchClass
    }

    /// Các nốt liên quan, dùng để chọn khoảng bàn phím hiển thị.
    public var involvedPitches: [Pitch] {
        switch kind {
        case .introduce(let p, _), .findKey(let p, _): return [p]
        case .nameQuiz(let p, let choices): return [p] + choices
        case .earTraining(let p, let range): return [p] + range
        case .sequence(_, let notes): return notes.flatMap(\.pitches)
        case .chord(_, let pitches): return pitches
        case .rhythm: return [P("C4")]
        case .theory: return []
        }
    }

    /// Dòng tiêu đề của bài tập.
    public func title(_ naming: NoteNaming) -> String {
        switch kind {
        case .introduce(let p, _): return "Nốt mới: \(p.name(naming))"
        case .findKey(let p, let style):
            switch style {
            case .name, .nameAndStaff: return "Nhấn phím \(p.name(naming))"
            case .staff: return "Đọc nốt và nhấn phím đúng"
            }
        case .nameQuiz: return "Nốt này tên là gì?"
        case .earTraining: return "Nghe và đánh lại nốt"
        case .sequence(let title, _): return title
        case .chord(let name, _): return "Đánh hợp âm \(name)"
        case .rhythm: return "Gõ theo tiết tấu"
        case .theory: return "Câu hỏi"
        }
    }
}
