import Foundation

/// Kết quả cuối cùng của một bài tập.
public struct ExerciseOutcome: Hashable {
    public var success: Bool
    public var mistakes: Int
    /// 0...1
    public var accuracy: Double

    public init(success: Bool, mistakes: Int, accuracy: Double) {
        self.success = success
        self.mistakes = mistakes
        self.accuracy = max(0, min(1, accuracy))
    }
}

/// Phản hồi cho mỗi nốt được đánh.
public struct NoteFeedback: Equatable {
    public var pitch: Pitch
    public var isCorrect: Bool
    /// Chỉ số bước vừa hoàn thành (cho bài đánh chuỗi nốt).
    public var completedStep: Int?
    /// Khác nil khi bài tập vừa kết thúc.
    public var outcome: ExerciseOutcome?

    public init(pitch: Pitch, isCorrect: Bool, completedStep: Int? = nil, outcome: ExerciseOutcome? = nil) {
        self.pitch = pitch
        self.isCorrect = isCorrect
        self.completedStep = completedStep
        self.outcome = outcome
    }
}

/// Chấm bài đánh theo "chế độ chờ": danh sách các bước, mỗi bước là một hoặc nhiều nốt
/// (hợp âm) phải được nhấn đủ (đang giữ cùng lúc) thì mới sang bước tiếp theo.
///
/// Dùng cho: giới thiệu nốt, tìm phím, nghe và đánh lại, chuỗi nốt, hợp âm và chế độ chờ của bài hát.
public final class StepEvaluator {
    public let steps: [[Pitch]]
    public let mode: MatchMode
    /// Số lỗi tối đa vẫn được tính là "đạt".
    public let allowedMistakes: Int

    public private(set) var stepIndex = 0
    public private(set) var mistakes = 0
    public private(set) var outcome: ExerciseOutcome?
    /// Các nốt đã thỏa mãn trong bước hiện tại.
    public private(set) var satisfied: Set<Int> = []
    /// Các phím đang được giữ.
    public private(set) var held: Set<Int> = []
    /// Bước hiện tại có yêu cầu giữ cùng lúc (hợp âm) hay không.
    private let simultaneous: Bool

    public init(steps: [[Pitch]], mode: MatchMode, allowedMistakes: Int = 0, chordsMustBeHeld: Bool = true) {
        self.steps = steps.filter { !$0.isEmpty }
        self.mode = mode
        self.allowedMistakes = allowedMistakes
        self.simultaneous = chordsMustBeHeld
    }

    public convenience init(exercise: Exercise, strictOctave: Bool) {
        let mode = exercise.matchMode(strictOctave: strictOctave)
        switch exercise.kind {
        case .introduce(let p, _), .findKey(let p, _), .earTraining(let p, _):
            self.init(steps: [[p]], mode: mode)
        case .sequence(_, let notes):
            let steps = notes.filter { !$0.isRest }.map(\.pitches)
            self.init(steps: steps, mode: mode, allowedMistakes: steps.count / 5)
        case .chord(_, let pitches):
            self.init(steps: [pitches], mode: mode, allowedMistakes: 1)
        case .nameQuiz, .theory, .rhythm:
            self.init(steps: [], mode: mode)
        }
    }

    public var isFinished: Bool { outcome != nil }
    public var currentStep: [Pitch]? { stepIndex < steps.count ? steps[stepIndex] : nil }
    public var progress: Double { steps.isEmpty ? 1 : Double(stepIndex) / Double(steps.count) }

    /// Các nốt trong bước hiện tại mà người học chưa nhấn.
    public var remainingInStep: [Pitch] {
        guard let step = currentStep else { return [] }
        return step.enumerated().filter { !satisfied.contains($0.offset) }.map(\.element)
    }

    @discardableResult
    public func noteOn(_ pitch: Pitch) -> NoteFeedback? {
        held.insert(pitch.midi)
        guard outcome == nil, let step = currentStep else { return nil }

        if let idx = step.indices.first(where: { !satisfied.contains($0) && step[$0].matches(pitch, mode: mode) }) {
            satisfied.insert(idx)
        } else if step.contains(where: { $0.matches(pitch, mode: mode) }) {
            // Nhấn lại một nốt đã đúng trong cùng hợp âm: bỏ qua.
            return NoteFeedback(pitch: pitch, isCorrect: true)
        } else {
            mistakes += 1
            return NoteFeedback(pitch: pitch, isCorrect: false)
        }

        // Với hợp âm: các nốt đã nhấn phải còn đang được giữ.
        if simultaneous && step.count > 1 {
            satisfied = Set(step.indices.filter { i in
                satisfied.contains(i) && held.contains(where: { step[i].matches(Pitch($0), mode: mode) })
            })
        }

        guard satisfied.count == step.count else {
            return NoteFeedback(pitch: pitch, isCorrect: true)
        }
        let completed = stepIndex
        stepIndex += 1
        satisfied = []
        if stepIndex >= steps.count {
            let total = steps.count
            let accuracy = Double(total) / Double(total + mistakes)
            outcome = ExerciseOutcome(success: mistakes <= allowedMistakes, mistakes: mistakes, accuracy: accuracy)
        }
        return NoteFeedback(pitch: pitch, isCorrect: true, completedStep: completed, outcome: outcome)
    }

    public func noteOff(_ pitch: Pitch) {
        held.remove(pitch.midi)
        guard simultaneous, let step = currentStep, step.count > 1 else { return }
        // Thả phím trước khi đủ hợp âm thì phải nhấn lại.
        satisfied = Set(satisfied.filter { i in
            held.contains(where: { step[i].matches(Pitch($0), mode: mode) })
        })
    }
}

// MARK: - Chấm theo nhịp

public enum TimingGrade: String, Codable {
    case perfect
    case good
    case miss
}

public struct TimedResult: Hashable {
    public var perfect: Int
    public var good: Int
    public var miss: Int
    /// Nốt sai cao độ hoặc gõ thừa.
    public var wrong: Int

    public var total: Int { perfect + good + miss }

    /// Điểm 0...1
    public var score: Double {
        guard total > 0 else { return 0 }
        let raw = (Double(perfect) + 0.7 * Double(good)) / Double(total) - 0.03 * Double(wrong)
        return max(0, min(1, raw))
    }

    public var stars: Int {
        switch score {
        case 0.9...: return 3
        case 0.75..<0.9: return 2
        case 0.5..<0.75: return 1
        default: return 0
        }
    }

    public var outcome: ExerciseOutcome {
        ExerciseOutcome(success: score >= 0.65, mistakes: miss + wrong, accuracy: score)
    }
}

/// Chấm điểm khi chơi theo nhịp (bài hát chế độ "theo nhịp" và bài gõ tiết tấu).
public final class TimedNoteTracker {
    public struct Target: Hashable {
        /// Chỉ số nốt trong bản nhạc gốc.
        public let noteIndex: Int
        /// Thời điểm (giây) tính từ phách 0.
        public let time: Double
        /// nil = phím nào cũng được (bài tiết tấu).
        public let pitch: Pitch?
        public internal(set) var grade: TimingGrade?
    }

    public private(set) var targets: [Target]
    public let mode: MatchMode
    public let perfectWindow: Double
    public let goodWindow: Double
    public private(set) var wrong = 0

    public init(notes: [ScoreNote], secondsPerBeat: Double, mode: MatchMode, anyPitch: Bool = false,
                perfectWindow: Double = 0.1, goodWindow: Double = 0.24) {
        var t: [Target] = []
        for (i, n) in notes.enumerated() where !n.isRest {
            let time = n.beat * secondsPerBeat
            if anyPitch {
                t.append(Target(noteIndex: i, time: time, pitch: nil, grade: nil))
            } else {
                for p in n.pitches { t.append(Target(noteIndex: i, time: time, pitch: p, grade: nil)) }
            }
        }
        self.targets = t
        self.mode = mode
        self.perfectWindow = perfectWindow
        self.goodWindow = goodWindow
    }

    public convenience init(rhythm: RhythmPattern) {
        self.init(notes: rhythm.notes, secondsPerBeat: rhythm.secondsPerBeat, mode: .pitchClass, anyPitch: true,
                  perfectWindow: 0.09, goodWindow: min(0.22, rhythm.secondsPerBeat * 0.3))
    }

    /// Ghi nhận một nốt; trả về chỉ số target được khớp và mức đánh giá, hoặc nil nếu sai/thừa.
    @discardableResult
    public func noteOn(_ pitch: Pitch, at time: Double) -> (target: Int, grade: TimingGrade)? {
        var best: Int?
        var bestDelta = Double.infinity
        for (i, target) in targets.enumerated() where target.grade == nil {
            if let p = target.pitch, !p.matches(pitch, mode: mode) { continue }
            let delta = abs(target.time - time)
            if delta <= goodWindow && delta < bestDelta {
                best = i
                bestDelta = delta
            }
            if target.time > time + goodWindow { break }
        }
        guard let index = best else {
            wrong += 1
            return nil
        }
        let grade: TimingGrade = bestDelta <= perfectWindow ? .perfect : .good
        targets[index].grade = grade
        return (index, grade)
    }

    /// Đánh dấu trượt cho các nốt đã quá thời gian. Trả về chỉ số các target vừa bị trượt.
    @discardableResult
    public func expire(before time: Double) -> [Int] {
        var missed: [Int] = []
        for i in targets.indices where targets[i].grade == nil && targets[i].time + goodWindow < time {
            targets[i].grade = .miss
            missed.append(i)
        }
        return missed
    }

    public var isComplete: Bool { targets.allSatisfy { $0.grade != nil } }

    public func finish() -> TimedResult {
        expire(before: .infinity)
        return TimedResult(
            perfect: targets.filter { $0.grade == .perfect }.count,
            good: targets.filter { $0.grade == .good }.count,
            miss: targets.filter { $0.grade == .miss }.count,
            wrong: wrong
        )
    }
}
