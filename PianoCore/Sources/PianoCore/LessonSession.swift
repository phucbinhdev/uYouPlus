import Foundation

/// Tóm tắt khi kết thúc bài học.
public struct LessonSummary: Hashable {
    public var xp: Int
    /// 0...1
    public var accuracy: Double
    public var stars: Int
    public var mistakes: Int
    public var duration: TimeInterval
    public var passed: Bool
    public var perfect: Bool
}

/// Quản lý tiến trình một bài học kiểu Duolingo:
///  - mỗi bài tập làm sai sẽ bị trừ 1 tim và được đưa lại vào cuối hàng đợi;
///  - thanh tiến độ chỉ chạy khi làm đúng;
///  - hết tim thì bài học thất bại.
public struct LessonSession {
    public static let defaultHearts = 5

    public private(set) var queue: [Exercise]
    public private(set) var position = 0
    public private(set) var hearts: Int
    public let maxHearts: Int
    public let unlimitedHearts: Bool
    /// Số bài tập gốc (không tính bài làm lại).
    public let originalCount: Int
    public private(set) var completedIDs: Set<UUID> = []
    public private(set) var failedIDs: Set<UUID> = []
    public private(set) var totalMistakes = 0
    /// Số lần trả lời bài tập có chấm điểm.
    public private(set) var gradedAttempts = 0
    public private(set) var gradedCorrect = 0
    public let baseXP: Int

    public init(exercises: [Exercise], hearts: Int = LessonSession.defaultHearts, unlimitedHearts: Bool = false, baseXP: Int = 10) {
        self.queue = exercises
        self.hearts = hearts
        self.maxHearts = hearts
        self.unlimitedHearts = unlimitedHearts
        self.originalCount = exercises.count
        self.baseXP = baseXP
    }

    public var current: Exercise? { position < queue.count ? queue[position] : nil }
    public var isFailed: Bool { !unlimitedHearts && hearts <= 0 }
    public var isFinished: Bool { isFailed || position >= queue.count }

    /// 0...1 cho thanh tiến độ.
    public var progress: Double {
        guard originalCount > 0 else { return 1 }
        return Double(completedIDs.count) / Double(originalCount)
    }

    /// Ghi nhận kết quả bài tập hiện tại và chuyển sang bài tiếp theo.
    public mutating func record(success: Bool, mistakes: Int = 0) {
        guard let exercise = current else { return }
        if exercise.isGraded {
            gradedAttempts += 1
            totalMistakes += mistakes
        }
        if success || !exercise.isGraded {
            if exercise.isGraded { gradedCorrect += 1 }
            completedIDs.insert(exercise.id)
        } else {
            failedIDs.insert(exercise.id)
            if !unlimitedHearts { hearts -= 1 }
            // Đưa bài tập lại cuối hàng đợi để làm lại.
            queue.append(exercise)
        }
        position += 1
    }

    public func summary(duration: TimeInterval) -> LessonSummary {
        let accuracy = gradedAttempts == 0 ? 1 : Double(gradedCorrect) / Double(gradedAttempts)
        let passed = !isFailed && completedIDs.count == originalCount
        let perfect = passed && failedIDs.isEmpty && totalMistakes == 0
        let stars: Int
        if !passed {
            stars = 0
        } else if accuracy >= 0.95 {
            stars = 3
        } else if accuracy >= 0.75 {
            stars = 2
        } else {
            stars = 1
        }
        var xp = 0
        if passed {
            xp = baseXP + (perfect ? 5 : 0) + (stars == 3 && !perfect ? 2 : 0)
        }
        return LessonSummary(xp: xp, accuracy: accuracy, stars: stars, mistakes: totalMistakes,
                             duration: duration, passed: passed, perfect: perfect)
    }
}
