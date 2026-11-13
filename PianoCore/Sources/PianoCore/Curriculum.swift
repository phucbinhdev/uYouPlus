import Foundation

/// Kiểu câu hỏi luyện tập được sinh ngẫu nhiên.
public enum DrillStyle: String, Hashable, CaseIterable {
    /// "Nhấn phím Mi"
    case findByName
    /// Hiện nốt trên khuông, nhấn phím đúng.
    case findByStaff
    /// Hiện nốt trên khuông, chọn tên đúng.
    case nameQuiz
    /// Nghe và đánh lại.
    case ear
}

/// Một khối nội dung trong bài học.
public enum LessonBlock: Hashable {
    /// Các bài tập theo đúng thứ tự.
    case fixed([ExerciseKind])
    /// Các bài tập được xáo trộn thứ tự.
    case shuffled([ExerciseKind])
    /// Sinh ngẫu nhiên `count` câu hỏi từ tập nốt `pool`.
    case drill(pool: [Pitch], count: Int, styles: [DrillStyle])
}

public enum LessonKind: String, Hashable {
    case learn
    case practice
    case review
}

public struct Lesson: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// Tên biểu tượng SF Symbol.
    public let icon: String
    public let kind: LessonKind
    public let blocks: [LessonBlock]
    public let exactOctave: Bool
    public let hints: Bool

    public init(id: String, title: String, subtitle: String, icon: String, kind: LessonKind = .learn,
                exactOctave: Bool = false, hints: Bool = true, blocks: [LessonBlock]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.kind = kind
        self.exactOctave = exactOctave
        self.hints = hints
        self.blocks = blocks
    }

    public var baseXP: Int { kind == .review ? 15 : 10 }

    public func makeExercises() -> [Exercise] {
        var rng = SystemRandomNumberGenerator()
        return makeExercises(using: &rng)
    }

    public func makeExercises<R: RandomNumberGenerator>(using rng: inout R) -> [Exercise] {
        var result: [Exercise] = []
        for block in blocks {
            switch block {
            case .fixed(let kinds):
                for kind in kinds {
                    result.append(Exercise(Lesson.shuffleChoices(kind, rng: &rng), requiresExactOctave: exactOctave, showHints: hints))
                }
            case .shuffled(let kinds):
                for kind in kinds.shuffled(using: &rng) {
                    result.append(Exercise(Lesson.shuffleChoices(kind, rng: &rng), requiresExactOctave: exactOctave, showHints: hints))
                }
            case .drill(let pool, let count, let styles):
                result += Lesson.drill(pool: pool, count: count, styles: styles, rng: &rng)
                    .map { Exercise($0, requiresExactOctave: exactOctave, showHints: hints) }
            }
        }
        return result
    }

    /// Xáo trộn thứ tự đáp án của câu hỏi trắc nghiệm.
    static func shuffleChoices<R: RandomNumberGenerator>(_ kind: ExerciseKind, rng: inout R) -> ExerciseKind {
        switch kind {
        case .theory(let q, let choices, let answer, let explanation):
            let order = Array(choices.indices).shuffled(using: &rng)
            let newChoices = order.map { choices[$0] }
            let newAnswer = order.firstIndex(of: answer) ?? 0
            return .theory(question: q, choices: newChoices, answer: newAnswer, explanation: explanation)
        case .nameQuiz(let p, let choices):
            return .nameQuiz(p, choices: choices.shuffled(using: &rng))
        default:
            return kind
        }
    }

    static func drill<R: RandomNumberGenerator>(pool: [Pitch], count: Int, styles: [DrillStyle], rng: inout R) -> [ExerciseKind] {
        guard !pool.isEmpty, !styles.isEmpty else { return [] }
        var out: [ExerciseKind] = []
        var previous: Pitch?
        for _ in 0..<count {
            var candidates = pool.filter { $0 != previous }
            if candidates.isEmpty { candidates = pool }
            let pitch = candidates.randomElement(using: &rng)!
            previous = pitch
            let style = styles.randomElement(using: &rng)!
            switch style {
            case .findByName: out.append(.findKey(pitch, prompt: .name))
            case .findByStaff: out.append(.findKey(pitch, prompt: .staff))
            case .ear: out.append(.earTraining(pitch, range: pool))
            case .nameQuiz:
                out.append(.nameQuiz(pitch, choices: quizChoices(answer: pitch, pool: pool, rng: &rng)))
            }
        }
        return out
    }

    /// 4 lựa chọn có tên khác nhau, gồm đáp án đúng.
    static func quizChoices<R: RandomNumberGenerator>(answer: Pitch, pool: [Pitch], rng: inout R) -> [Pitch] {
        var choices = [answer]
        var usedNames: Set<String> = [answer.letterName()]
        for p in pool.shuffled(using: &rng) where choices.count < 4 && !usedNames.contains(p.letterName()) {
            choices.append(p)
            usedNames.insert(p.letterName())
        }
        // Bổ sung bằng các nốt lân cận nếu tập nốt quá nhỏ.
        var offset = 1
        while choices.count < 4 && offset < 12 {
            for candidate in [answer.transposed(offset), answer.transposed(-offset)]
            where choices.count < 4 && !candidate.isBlack && !usedNames.contains(candidate.letterName()) {
                choices.append(candidate)
                usedNames.insert(candidate.letterName())
            }
            offset += 1
        }
        return choices.shuffled(using: &rng)
    }
}

public struct CourseUnit: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let description: String
    /// Màu chủ đạo dạng hex, ví dụ "58CC02".
    public let colorHex: String
    public let lessons: [Lesson]
}

// MARK: - Giáo trình

public enum Curriculum {
    // Viết tắt để soạn nội dung gọn hơn.
    static func intro(_ n: String, _ tip: String) -> ExerciseKind { .introduce(P(n), tip: tip) }
    static func find(_ n: String, _ style: PromptStyle = .name) -> ExerciseKind { .findKey(P(n), prompt: style) }
    static func quiz(_ n: String, _ choices: String) -> ExerciseKind {
        .nameQuiz(P(n), choices: choices.split(separator: " ").map { P(String($0)) })
    }
    static func seq(_ title: String, _ score: String) -> ExerciseKind {
        .sequence(title: title, notes: (try? ScoreParser.parse(score)) ?? [])
    }
    static func chord(_ name: String, _ notes: String) -> ExerciseKind {
        .chord(name: name, pitches: notes.split(separator: " ").map { P(String($0)) })
    }
    static func rhythm(_ score: String, tempo: Double = 72) -> ExerciseKind {
        .rhythm(RhythmPattern(score: score, tempo: tempo))
    }
    static func theory(_ q: String, _ choices: [String], _ answer: Int = 0, _ explanation: String? = nil) -> ExerciseKind {
        .theory(question: q, choices: choices, answer: answer, explanation: explanation)
    }
    static func pitches(_ s: String) -> [Pitch] { s.split(separator: " ").map { P(String($0)) } }

    static let whiteC4toB4 = pitches("C4 D4 E4 F4 G4 A4 B4")

    public static let units: [CourseUnit] = [
        // MARK: Chương 1
        CourseUnit(id: "u1", title: "Làm quen bàn phím",
             description: "Tìm các nốt Đô Rê Mi Fa Sol La Si trên đàn", colorHex: "58CC02", lessons: [
                Lesson(id: "u1l1", title: "Nốt Đô", subtitle: "Tìm phím Đô nhờ nhóm 2 phím đen", icon: "music.note", blocks: [
                    .fixed([
                        theory("Phím đen trên đàn piano được xếp thành những nhóm nào?",
                               ["Nhóm 2 phím và nhóm 3 phím", "Nhóm 4 phím", "Không theo nhóm nào", "Nhóm 1 phím"], 0,
                               "Phím đen xếp xen kẽ thành nhóm 2 và nhóm 3. Nhờ vậy ta định vị các nốt rất dễ."),
                        intro("C4", "Phím Đô (C) nằm ngay bên trái nhóm 2 phím đen. Đô ở khoảng giữa đàn gọi là Đô giữa."),
                        find("C4"),
                        theory("Phím Đô nằm ở đâu?",
                               ["Bên trái nhóm 2 phím đen", "Bên phải nhóm 3 phím đen", "Giữa 2 phím đen", "Bên trái nhóm 3 phím đen"], 0),
                        find("C4"), find("C4")
                    ])
                ]),
                Lesson(id: "u1l2", title: "Rê và Mi", subtitle: "Hai nốt tiếp theo sau Đô", icon: "music.note", blocks: [
                    .fixed([
                        intro("D4", "Rê (D) nằm giữa 2 phím đen của nhóm 2."),
                        find("D4"),
                        intro("E4", "Mi (E) nằm ngay bên phải nhóm 2 phím đen."),
                        find("E4")
                    ]),
                    .drill(pool: pitches("C4 D4 E4"), count: 5, styles: [.findByName]),
                    .fixed([seq("Đánh Đô – Rê – Mi", "C4 D4 E4")])
                ]),
                Lesson(id: "u1l3", title: "Đô Rê Mi", subtitle: "Đánh những giai điệu 3 nốt", icon: "music.quarternote.3", kind: .practice, blocks: [
                    .fixed([seq("Đi lên", "C4 D4 E4"), seq("Đi xuống", "E4 D4 C4")]),
                    .drill(pool: pitches("C4 D4 E4"), count: 3, styles: [.findByName]),
                    .fixed([
                        seq("Lên rồi xuống", "C4 D4 E4 D4 C4"),
                        .earTraining(P("C4"), range: pitches("C4 D4 E4")),
                        seq("Mary có chú cừu non (đoạn đầu)", "E4 D4 C4 D4 E4 E4 E4:h")
                    ])
                ]),
                Lesson(id: "u1l4", title: "Fa và Sol", subtitle: "Định vị nhờ nhóm 3 phím đen", icon: "music.note", blocks: [
                    .fixed([
                        intro("F4", "Fa (F) nằm ngay bên trái nhóm 3 phím đen."),
                        find("F4"),
                        intro("G4", "Sol (G) nằm giữa phím đen thứ nhất và thứ hai của nhóm 3."),
                        find("G4")
                    ]),
                    .drill(pool: pitches("C4 D4 E4 F4 G4"), count: 5, styles: [.findByName]),
                    .fixed([seq("Năm nốt đi lên", "C4 D4 E4 F4 G4"), seq("Năm nốt đi xuống", "G4 F4 E4 D4 C4")])
                ]),
                Lesson(id: "u1l5", title: "La, Si và Đô cao", subtitle: "Hoàn thành một quãng tám", icon: "music.note", blocks: [
                    .fixed([
                        intro("A4", "La (A) nằm giữa phím đen thứ hai và thứ ba của nhóm 3."),
                        find("A4"),
                        intro("B4", "Si (B) nằm ngay bên phải nhóm 3 phím đen."),
                        find("B4"),
                        theory("Nốt nào đứng ngay sau Si?", ["Đô", "La", "Rê", "Fa"], 0,
                               "Sau Si lại là Đô – bắt đầu một quãng tám mới!")
                    ]),
                    .drill(pool: whiteC4toB4, count: 5, styles: [.findByName]),
                    .fixed([seq("Cả quãng tám", "C4 D4 E4 F4 G4 A4 B4 C5")])
                ]),
                Lesson(id: "u1l6", title: "Ôn tập chương 1", subtitle: "7 nốt nhạc cơ bản", icon: "star.fill", kind: .review, blocks: [
                    .shuffled([
                        theory("Một quãng tám có bao nhiêu phím trắng (nốt cơ bản)?", ["7", "5", "12", "8"], 0),
                        theory("Nốt nào nằm ngay sau Mi?", ["Fa", "Sol", "Rê", "Si"], 0),
                        theory("Phím nằm bên trái nhóm 3 phím đen là?", ["Fa", "Đô", "Si", "Mi"], 0)
                    ]),
                    .drill(pool: whiteC4toB4, count: 8, styles: [.findByName, .findByName, .ear])
                ])
             ]),

        // MARK: Chương 2
        CourseUnit(id: "u2", title: "Vị trí 5 ngón tay",
             description: "Đặt tay đúng và chơi những giai điệu đầu tiên", colorHex: "1CB0F6", lessons: [
                Lesson(id: "u2l1", title: "Số ngón tay", subtitle: "Ngón 1 đến ngón 5", icon: "hand.raised.fill", blocks: [
                    .fixed([
                        theory("Ngón cái được đánh số mấy?", ["1", "5", "0", "2"], 0,
                               "Ngón cái = 1, ngón trỏ = 2, ngón giữa = 3, ngón áp út = 4, ngón út = 5."),
                        theory("Ở tư thế Đô, ngón 3 (ngón giữa) tay phải đặt lên phím nào?", ["Mi", "Rê", "Fa", "Đô"], 0,
                               "Ngón 1 → Đô, 2 → Rê, 3 → Mi, 4 → Fa, 5 → Sol."),
                        seq("Từng ngón đi lên", "C4@1 D4@2 E4@3 F4@4 G4@5"),
                        seq("Từng ngón đi xuống", "G4@5 F4@4 E4@3 D4@2 C4@1"),
                        seq("Ngón 1 – 3 – 5", "C4@1 E4@3 G4@5 E4@3 C4@1")
                    ])
                ]),
                Lesson(id: "u2l2", title: "Bước và nhảy", subtitle: "Phím kề nhau và cách quãng", icon: "figure.walk", kind: .practice, blocks: [
                    .fixed([
                        theory("Từ Đô lên Mi (bỏ qua Rê) gọi là gì?",
                               ["Bước nhảy", "Bước liền", "Quãng tám", "Đồng âm"], 0,
                               "Đi sang phím kề bên là bước liền; bỏ qua một phím là bước nhảy (quãng 3)."),
                        seq("Bước liền", "C4 D4 C4 D4 E4 D4 E4 F4"),
                        seq("Bước nhảy", "C4 E4 D4 F4 E4 G4"),
                        seq("Nhảy đi xuống", "G4 E4 F4 D4 E4 C4")
                    ])
                ]),
                Lesson(id: "u2l3", title: "Bài: Bánh nóng", subtitle: "Giai điệu đầu tiên trọn vẹn", icon: "music.note.list", blocks: [
                    .fixed([
                        seq("Câu 1", "E4@3 D4@2 C4:h@1"),
                        seq("Câu 2", "C4:e@1 C4:e C4:e C4:e D4:e@2 D4:e D4:e D4:e"),
                        seq("Cả bài", "E4 D4 C4:h E4 D4 C4:h C4:e C4:e C4:e C4:e D4:e D4:e D4:e D4:e E4 D4 C4:h")
                    ])
                ]),
                Lesson(id: "u2l4", title: "Bài: Mary có chú cừu non", subtitle: "Giai điệu dân ca Mỹ", icon: "music.note.list", blocks: [
                    .fixed([
                        seq("Câu 1", "E4@3 D4@2 C4@1 D4 E4 E4 E4:h"),
                        seq("Câu 2", "D4 D4 D4:h E4 G4@5 G4:h"),
                        seq("Câu 3", "E4 D4 C4 D4 E4 E4 E4 E4"),
                        seq("Câu 4", "D4 D4 E4 D4 C4:w")
                    ])
                ]),
                Lesson(id: "u2l5", title: "Bài: Khúc hoan ca", subtitle: "Ode to Joy – Beethoven", icon: "music.note.list", blocks: [
                    .fixed([
                        seq("Câu 1", "E4@3 E4 F4@4 G4@5 G4 F4 E4 D4@2"),
                        seq("Câu 2", "C4@1 C4 D4 E4 E4:q. D4:e D4:h"),
                        seq("Câu 3", "E4 E4 F4 G4 G4 F4 E4 D4"),
                        seq("Câu 4", "C4 C4 D4 E4 D4:q. C4:e C4:h")
                    ])
                ]),
                Lesson(id: "u2l6", title: "Ôn tập chương 2", subtitle: "Ôn các giai điệu", icon: "star.fill", kind: .review, blocks: [
                    .shuffled([
                        seq("Bánh nóng", "E4 D4 C4:h E4 D4 C4:h"),
                        seq("Mary có chú cừu non", "E4 D4 C4 D4 E4 E4 E4:h"),
                        seq("Khúc hoan ca", "E4 E4 F4 G4 G4 F4 E4 D4"),
                        seq("Kìa con bướm vàng", "C4 D4 E4 C4 C4 D4 E4 C4")
                    ]),
                    .drill(pool: pitches("C4 D4 E4 F4 G4"), count: 4, styles: [.ear])
                ])
             ]),

        // MARK: Chương 3
        CourseUnit(id: "u3", title: "Đọc nốt khóa Sol",
             description: "Đọc nốt nhạc trên khuông", colorHex: "CE82FF", lessons: [
                Lesson(id: "u3l1", title: "Khuông nhạc", subtitle: "Dòng kẻ, khe và khóa Sol", icon: "music.note.house", blocks: [
                    .fixed([
                        theory("Khuông nhạc có mấy dòng kẻ?", ["5", "4", "6", "3"], 0),
                        theory("Khóa Sol cho biết điều gì?",
                               ["Nốt Sol nằm trên dòng kẻ thứ 2", "Bài nhạc chơi nhanh", "Chỉ dùng tay trái", "Nốt Đô nằm trên dòng 1"], 0,
                               "Vòng xoắn của khóa Sol ôm quanh dòng kẻ thứ 2 – đó là nốt Sol."),
                        find("C4", .nameAndStaff), find("D4", .nameAndStaff), find("E4", .nameAndStaff),
                        quiz("C4", "C4 D4 E4 F4"), quiz("E4", "C4 D4 E4 G4")
                    ])
                ]),
                Lesson(id: "u3l2", title: "Đô giữa trên khuông", subtitle: "Dòng kẻ phụ", icon: "music.note", blocks: [
                    .fixed([
                        theory("Đô giữa nằm ở đâu trên khóa Sol?",
                               ["Trên một dòng kẻ phụ bên dưới khuông", "Dòng kẻ thứ nhất", "Khe thứ ba", "Dòng kẻ trên cùng"], 0)
                    ]),
                    .drill(pool: pitches("C4 D4 E4"), count: 7, styles: [.findByStaff, .nameQuiz])
                ]),
                Lesson(id: "u3l3", title: "Fa và Sol trên khuông", subtitle: "Khe 1 và dòng 2", icon: "music.note", blocks: [
                    .fixed([find("F4", .nameAndStaff), find("G4", .nameAndStaff)]),
                    .drill(pool: pitches("C4 D4 E4 F4 G4"), count: 8, styles: [.findByStaff, .nameQuiz])
                ]),
                Lesson(id: "u3l4", title: "Nốt trên dòng kẻ", subtitle: "Mi – Sol – Si – Rê – Fa", icon: "line.3.horizontal", blocks: [
                    .fixed([
                        theory("Các nốt nằm trên 5 dòng kẻ khóa Sol (từ dưới lên) là?",
                               ["Mi Sol Si Rê Fa", "Fa La Đô Mi", "Đô Mi Sol Si Rê", "Rê Fa La Đô Mi"], 0),
                        find("B4", .nameAndStaff), find("D5", .nameAndStaff), find("F5", .nameAndStaff)
                    ]),
                    .drill(pool: pitches("E4 G4 B4 D5 F5"), count: 8, styles: [.findByStaff, .nameQuiz])
                ]),
                Lesson(id: "u3l5", title: "Nốt trong khe", subtitle: "Fa – La – Đô – Mi", icon: "line.3.horizontal", blocks: [
                    .fixed([
                        theory("Các nốt nằm trong 4 khe khóa Sol (từ dưới lên) là?",
                               ["Fa La Đô Mi", "Mi Sol Si Rê", "Sol Si Rê Fa", "Đô Mi Sol Si"], 0),
                        find("A4", .nameAndStaff), find("C5", .nameAndStaff), find("E5", .nameAndStaff)
                    ]),
                    .drill(pool: pitches("F4 A4 C5 E5"), count: 8, styles: [.findByStaff, .nameQuiz])
                ]),
                Lesson(id: "u3l6", title: "Đọc và đánh", subtitle: "Đọc giai điệu trên khuông", icon: "eye.fill", kind: .practice, hints: false, blocks: [
                    .fixed([
                        seq("Đọc và đánh", "C4 E4 G4 E4 C4:h"),
                        seq("Đọc và đánh", "G4 A4 B4 C5:h"),
                        seq("Đọc và đánh", "C5 B4 A4 G4 F4 E4 D4 C4"),
                        seq("Đọc và đánh", "E4 G4 F4 A4 G4 B4 C5:h")
                    ])
                ]),
                Lesson(id: "u3l7", title: "Ôn tập đọc nốt", subtitle: "Từ Đô giữa đến Sol cao", icon: "star.fill", kind: .review, hints: false, blocks: [
                    .drill(pool: pitches("C4 D4 E4 F4 G4 A4 B4 C5 D5 E5 F5 G5"), count: 12, styles: [.findByStaff, .nameQuiz])
                ])
             ]),

        // MARK: Chương 4
        CourseUnit(id: "u4", title: "Nhịp điệu",
             description: "Nốt đen, nốt trắng, nốt tròn và dấu lặng", colorHex: "FF9600", lessons: [
                Lesson(id: "u4l1", title: "Nốt đen", subtitle: "1 phách", icon: "metronome.fill", blocks: [
                    .fixed([
                        theory("Nốt đen dài mấy phách?", ["1 phách", "2 phách", "4 phách", "Nửa phách"], 0),
                        rhythm("C4 C4 C4 C4 | C4 C4 C4 C4", tempo: 66),
                        rhythm("C4 C4 C4 C4 | C4 C4 C4 C4", tempo: 80)
                    ])
                ]),
                Lesson(id: "u4l2", title: "Nốt trắng", subtitle: "2 phách", icon: "metronome.fill", blocks: [
                    .fixed([
                        theory("Nốt trắng dài mấy phách?", ["2 phách", "1 phách", "3 phách", "4 phách"], 0),
                        rhythm("C4:h C4:h | C4 C4 C4:h"),
                        rhythm("C4 C4:h C4 | C4:h C4:h"),
                        seq("Giai điệu nốt trắng", "C4:h E4:h G4:h E4:h C4:w")
                    ])
                ]),
                Lesson(id: "u4l3", title: "Nốt tròn & dấu lặng", subtitle: "4 phách và khoảng nghỉ", icon: "pause.circle.fill", blocks: [
                    .fixed([
                        theory("Nốt tròn dài mấy phách?", ["4 phách", "2 phách", "3 phách", "1 phách"], 0),
                        theory("Dấu lặng nghĩa là gì?", ["Nghỉ, không đánh", "Đánh thật mạnh", "Giữ phím thật lâu", "Đánh thật nhanh"], 0),
                        rhythm("C4:w | C4 R C4 R"),
                        rhythm("C4 C4 R C4 | C4:h R:h")
                    ])
                ]),
                Lesson(id: "u4l4", title: "Móc đơn", subtitle: "Nửa phách", icon: "metronome.fill", blocks: [
                    .fixed([
                        theory("Hai nốt móc đơn dài bằng?", ["Một nốt đen", "Hai nốt đen", "Một nốt trắng", "Một nốt tròn"], 0),
                        rhythm("C4:e C4:e C4 C4:e C4:e C4 | C4:e C4:e C4:e C4:e C4:h", tempo: 66),
                        rhythm("C4 C4:e C4:e C4 C4 | C4:e C4:e C4 C4:h", tempo: 66)
                    ])
                ]),
                Lesson(id: "u4l5", title: "Dấu chấm dôi", subtitle: "Thêm một nửa trường độ", icon: "smallcircle.filled.circle", blocks: [
                    .fixed([
                        theory("Nốt trắng chấm dôi dài mấy phách?", ["3 phách", "2 phách", "2 phách rưỡi", "4 phách"], 0,
                               "Dấu chấm dôi cộng thêm một nửa trường độ: 2 + 1 = 3 phách."),
                        rhythm("C4:h. C4 | C4:q. C4:e C4:h", tempo: 66),
                        rhythm("C4:q. C4:e C4 C4 | C4:h. R", tempo: 66)
                    ])
                ]),
                Lesson(id: "u4l6", title: "Ôn tập nhịp điệu", subtitle: "Kết hợp giai điệu và tiết tấu", icon: "star.fill", kind: .review, blocks: [
                    .shuffled([
                        rhythm("C4 C4 C4:h | C4:e C4:e C4 C4:h"),
                        rhythm("C4:q. C4:e C4 R | C4:w"),
                        seq("Jingle Bells", "E4 E4 E4:h E4 E4 E4:h E4 G4 C4:q. D4:e E4:w"),
                        seq("Nông trại vui vẻ", "G4 G4 G4 D4 E4 E4 D4:h")
                    ])
                ])
             ]),

        // MARK: Chương 5
        CourseUnit(id: "u5", title: "Phím đen",
             description: "Dấu thăng ♯ và dấu giáng ♭", colorHex: "FF4B4B", lessons: [
                Lesson(id: "u5l1", title: "Dấu thăng ♯", subtitle: "Cao lên nửa cung", icon: "number", blocks: [
                    .fixed([
                        theory("Dấu thăng (♯) làm nốt nhạc thế nào?",
                               ["Cao lên nửa cung", "Thấp xuống nửa cung", "Cao lên một quãng tám", "Không thay đổi"], 0,
                               "Nửa cung là khoảng cách giữa hai phím liền nhau (kể cả phím đen)."),
                        intro("F#4", "Fa♯ là phím đen ngay bên phải Fa."),
                        intro("C#4", "Đô♯ là phím đen ngay bên phải Đô.")
                    ]),
                    .drill(pool: pitches("C4 C#4 F4 F#4 G4 G#4"), count: 6, styles: [.findByName])
                ]),
                Lesson(id: "u5l2", title: "Dấu giáng ♭", subtitle: "Thấp xuống nửa cung", icon: "textformat.alt", blocks: [
                    .fixed([
                        theory("Dấu giáng (♭) làm nốt nhạc thế nào?",
                               ["Thấp xuống nửa cung", "Cao lên nửa cung", "Dài gấp đôi", "Không thay đổi"], 0),
                        intro("Bb4", "Si♭ là phím đen ngay bên trái Si."),
                        intro("Eb4", "Mi♭ là phím đen ngay bên trái Mi."),
                        theory("Đô♯ và Rê♭ là?", ["Cùng một phím đen", "Hai phím khác nhau", "Hai phím trắng", "Không tồn tại"], 0)
                    ]),
                    .drill(pool: pitches("Eb4 E4 Bb4 B4 Ab4 Db4"), count: 6, styles: [.findByName])
                ]),
                Lesson(id: "u5l3", title: "Đi từng nửa cung", subtitle: "Gam nửa cung", icon: "stairs", kind: .practice, blocks: [
                    .fixed([
                        seq("Nửa cung đi lên", "C4 C#4 D4 D#4 E4 F4 F#4 G4"),
                        seq("Nửa cung đi xuống", "G4 Gb4 F4 E4 Eb4 D4 Db4 C4")
                    ]),
                    .drill(pool: pitches("C#4 Eb4 F#4 G#4 Bb4"), count: 6, styles: [.findByStaff, .findByName])
                ]),
                Lesson(id: "u5l4", title: "Bài: Für Elise", subtitle: "Đoạn mở đầu nổi tiếng", icon: "music.note.list", blocks: [
                    .fixed([
                        seq("Câu 1", "E5:s D#5:s E5:s D#5:s E5:s B4:s D5:s C5:s A4:e"),
                        seq("Câu 2", "C4:s E4:s A4:s B4:e E4:s G#4:s B4:s C5:e"),
                        seq("Cả đoạn", "E5:s D#5:s E5:s D#5:s E5:s B4:s D5:s C5:s A4:e C4:s E4:s A4:s B4:e E4:s C5:s B4:s A4:q")
                    ])
                ])
             ]),

        // MARK: Chương 6
        CourseUnit(id: "u6", title: "Hợp âm",
             description: "Nhiều nốt vang lên cùng lúc", colorHex: "2EC4B6", lessons: [
                Lesson(id: "u6l1", title: "Hợp âm Đô trưởng", subtitle: "Đô – Mi – Sol", icon: "pianokeys", blocks: [
                    .fixed([
                        theory("Hợp âm là gì?", ["Nhiều nốt vang lên cùng lúc", "Một nốt rất dài", "Hai bài hát", "Một ô nhịp"], 0),
                        theory("Hợp âm Đô trưởng gồm những nốt nào?", ["Đô – Mi – Sol", "Đô – Rê – Mi", "Đô – Fa – La", "Rê – Fa – La"], 0,
                               "Hợp âm ba gồm nốt gốc, nốt cách 2 phím trắng và nốt cách 4 phím trắng."),
                        chord("Đô trưởng (C)", "C4 E4 G4"),
                        chord("Đô trưởng (C)", "C4 E4 G4"),
                        seq("Rải hợp âm", "C4 E4 G4 E4 C4:h")
                    ])
                ]),
                Lesson(id: "u6l2", title: "Fa trưởng & Sol trưởng", subtitle: "Hai hợp âm quan trọng", icon: "pianokeys", blocks: [
                    .fixed([
                        theory("Hợp âm Fa trưởng (F) gồm những nốt nào?", ["Fa – La – Đô", "Fa – Sol – La", "Mi – Sol – Si", "Fa – Si – Rê"], 0),
                        chord("Fa trưởng (F)", "F4 A4 C5"),
                        theory("Hợp âm Sol trưởng (G) gồm những nốt nào?", ["Sol – Si – Rê", "Sol – La – Si", "Sol – Đô – Mi", "La – Đô – Mi"], 0),
                        chord("Sol trưởng (G)", "G4 B4 D5")
                    ]),
                    .shuffled([chord("Đô trưởng (C)", "C4 E4 G4"), chord("Fa trưởng (F)", "F4 A4 C5"), chord("Sol trưởng (G)", "G4 B4 D5")])
                ]),
                Lesson(id: "u6l3", title: "Hợp âm thứ", subtitle: "Âm sắc buồn hơn", icon: "pianokeys", blocks: [
                    .fixed([
                        theory("Hợp âm thứ thường mang cảm giác gì?", ["Buồn, trầm lắng", "Vui tươi, sáng sủa", "Không có âm thanh", "Rất to"], 0),
                        chord("La thứ (Am)", "A4 C5 E5"),
                        chord("Rê thứ (Dm)", "D4 F4 A4"),
                        chord("Mi thứ (Em)", "E4 G4 B4")
                    ]),
                    .shuffled([chord("La thứ (Am)", "A4 C5 E5"), chord("Rê thứ (Dm)", "D4 F4 A4")])
                ]),
                Lesson(id: "u6l4", title: "Vòng hợp âm", subtitle: "C – F – G – C", icon: "arrow.triangle.2.circlepath", kind: .practice, blocks: [
                    .fixed([
                        seq("Vòng C – F – G – C", "C4+E4+G4:w F4+A4+C5:w G4+B4+D5:w C4+E4+G4:w"),
                        theory("Vòng hợp âm là gì?",
                               ["Chuỗi hợp âm lặp lại làm nền cho bài hát", "Một hợp âm rất dài", "Gam đi lên rồi đi xuống", "Nhịp của bài hát"], 0),
                        seq("Vòng C – Am – F – G", "C4+E4+G4:w A4+C5+E5:w F4+A4+C5:w G4+B4+D5:w"),
                        seq("Vòng C – G – Am – F", "C4+E4+G4:w G4+B4+D5:w A4+C5+E5:w F4+A4+C5:w")
                    ])
                ]),
                Lesson(id: "u6l5", title: "Ôn tập hợp âm", subtitle: "Trưởng và thứ", icon: "star.fill", kind: .review, blocks: [
                    .shuffled([
                        chord("Đô trưởng (C)", "C4 E4 G4"), chord("Fa trưởng (F)", "F4 A4 C5"), chord("Sol trưởng (G)", "G4 B4 D5"),
                        chord("La thứ (Am)", "A4 C5 E5"), chord("Rê thứ (Dm)", "D4 F4 A4"),
                        theory("Hợp âm La thứ (Am) gồm những nốt nào?", ["La – Đô – Mi", "La – Đô♯ – Mi", "La – Si – Đô", "Sol – Si – Rê"], 0)
                    ])
                ])
             ]),

        // MARK: Chương 7
        CourseUnit(id: "u7", title: "Tay trái & khóa Fa",
             description: "Chơi những nốt trầm", colorHex: "E5559A", lessons: [
                Lesson(id: "u7l1", title: "Khóa Fa", subtitle: "Khóa của những nốt trầm", icon: "music.note", blocks: [
                    .fixed([
                        theory("Khóa Fa thường dùng cho phần nào?", ["Tay trái, nốt trầm", "Tay phải, nốt cao", "Chỉ để hát", "Trống"], 0),
                        theory("Dòng kẻ thứ 4 của khóa Fa là nốt gì?", ["Fa", "Sol", "Đô", "La"], 0,
                               "Hai chấm của khóa Fa ôm lấy dòng kẻ thứ 4 – đó là nốt Fa (F3)."),
                        intro("C3", "Đô3 – thấp hơn Đô giữa một quãng tám. Đặt ngón út (5) tay trái ở đây."),
                        intro("G3", "Sol3 – ngón cái (1) tay trái đặt ở đây."),
                        find("F3", .nameAndStaff)
                    ])
                ]),
                Lesson(id: "u7l2", title: "Tư thế Đô tay trái", subtitle: "Ngón 5 trên Đô3", icon: "hand.raised.fill", blocks: [
                    .fixed([
                        seq("Đi lên", "C3@5 D3@4 E3@3 F3@2 G3@1"),
                        seq("Đi xuống", "G3@1 F3@2 E3@3 D3@4 C3@5"),
                        seq("Ngón 5 – 3 – 1", "C3@5 E3@3 G3@1 E3@3 C3:h@5")
                    ])
                ]),
                Lesson(id: "u7l3", title: "Đọc nốt khóa Fa", subtitle: "Đô3 đến Sol3", icon: "eye.fill", hints: false, blocks: [
                    .drill(pool: pitches("C3 D3 E3 F3 G3"), count: 8, styles: [.findByStaff, .nameQuiz])
                ]),
                Lesson(id: "u7l4", title: "Bè trầm", subtitle: "Đệm cho giai điệu", icon: "waveform", kind: .practice, blocks: [
                    .fixed([
                        seq("Bè trầm 1", "C3:h G3:h F3:h C3:h G3:h G3:h C3:w"),
                        seq("Bè trầm 2", "C3 E3 G3 E3 F3 A3 C4 A3 G3 B3 D4 B3 C3:w")
                    ]),
                    .drill(pool: pitches("C3 D3 E3 F3 G3"), count: 3, styles: [.ear])
                ])
             ]),

        // MARK: Chương 8
        CourseUnit(id: "u8", title: "Gam & bài hát",
             description: "Kỹ thuật luồn ngón và những bài hát dài hơn", colorHex: "FFC800", lessons: [
                Lesson(id: "u8l1", title: "Luồn ngón cái", subtitle: "Gam Đô trưởng", icon: "arrow.up.right", blocks: [
                    .fixed([
                        theory("Khi đánh gam Đô trưởng tay phải, sau Mi (ngón 3) thì ngón nào đánh Fa?",
                               ["Ngón cái (1) luồn xuống dưới", "Ngón 4", "Ngón 5", "Ngón 2"], 0),
                        seq("Gam Đô trưởng đi lên", "C4@1 D4@2 E4@3 F4@1 G4@2 A4@3 B4@4 C5@5"),
                        seq("Gam Đô trưởng đi xuống", "C5@5 B4@4 A4@3 G4@2 F4@1 E4@3 D4@2 C4@1")
                    ])
                ]),
                Lesson(id: "u8l2", title: "Gam Sol trưởng", subtitle: "Gam có một dấu thăng", icon: "arrow.up.right", blocks: [
                    .fixed([
                        theory("Gam Sol trưởng có dấu hóa nào?", ["Fa♯", "Si♭", "Đô♯", "Không có"], 0),
                        seq("Gam Sol trưởng đi lên", "G4@1 A4@2 B4@3 C5@1 D5@2 E5@3 F#5@4 G5@5"),
                        seq("Gam Sol trưởng đi xuống", "G5@5 F#5@4 E5@3 D5@2 C5@1 B4@3 A4@2 G4@1")
                    ])
                ]),
                Lesson(id: "u8l3", title: "Hợp âm rải", subtitle: "Arpeggio", icon: "waveform.path", kind: .practice, blocks: [
                    .fixed([
                        seq("Rải Đô trưởng", "C4 E4 G4 C5 G4 E4 C4:h"),
                        seq("Rải Fa trưởng", "F4 A4 C5 F5 C5 A4 F4:h"),
                        seq("Rải Sol trưởng", "G4 B4 D5 G5 D5 B4 G4:h")
                    ])
                ]),
                Lesson(id: "u8l4", title: "Bài: Chúc mừng sinh nhật", subtitle: "Happy Birthday", icon: "gift.fill", blocks: [
                    .fixed([
                        seq("Câu 1", "G4:e. G4:s A4 G4 C5 B4:h"),
                        seq("Câu 2", "G4:e. G4:s A4 G4 D5 C5:h"),
                        seq("Câu 3", "G4:e. G4:s G5 E5 C5 B4 A4"),
                        seq("Câu 4", "F5:e. F5:s E5 C5 D5 C5:h.")
                    ])
                ]),
                Lesson(id: "u8l5", title: "Bài: Canon", subtitle: "Pachelbel", icon: "music.note.list", blocks: [
                    .fixed([
                        seq("Câu 1", "E5:h D5:h C5:h B4:h A4:h G4:h A4:h B4:h"),
                        seq("Câu 2", "E5 D5 C5 B4 A4 G4 A4 B4"),
                        seq("Câu 3", "C5 B4 A4 G4 F4 E4 F4 D4 C4:w")
                    ])
                ]),
                Lesson(id: "u8l6", title: "Tổng ôn", subtitle: "Thử thách cuối cùng", icon: "trophy.fill", kind: .review, blocks: [
                    .drill(pool: pitches("C4 D4 E4 F4 G4 A4 B4 C5 D5 E5"), count: 6, styles: [.findByStaff, .nameQuiz, .ear]),
                    .shuffled([
                        chord("Sol trưởng (G)", "G4 B4 D5"),
                        seq("Gam Đô trưởng", "C4 D4 E4 F4 G4 A4 B4 C5"),
                        rhythm("C4:q. C4:e C4 C4 | C4:h C4:h")
                    ])
                ])
             ])
    ]

    public static var allLessons: [Lesson] { units.flatMap(\.lessons) }

    public static func lesson(id: String) -> Lesson? { allLessons.first { $0.id == id } }

    public static func unit(containing lessonID: String) -> CourseUnit? {
        units.first { $0.lessons.contains { $0.id == lessonID } }
    }

    /// Bài học được mở khi bài trước đó đã hoàn thành.
    public static func isUnlocked(_ lessonID: String, progress: UserProgress) -> Bool {
        let lessons = allLessons
        guard let idx = lessons.firstIndex(where: { $0.id == lessonID }) else { return false }
        if idx == 0 { return true }
        return progress.isCompleted(lessons[idx - 1].id)
    }

    /// Bài học tiếp theo cần học (bài đầu tiên chưa hoàn thành).
    public static func nextLesson(progress: UserProgress) -> Lesson? {
        allLessons.first { !progress.isCompleted($0.id) }
    }
}
