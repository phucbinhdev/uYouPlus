import Foundation

/// Kết quả tốt nhất của một bài học.
public struct LessonRecord: Codable, Hashable {
    public var stars: Int
    public var bestAccuracy: Double
    public var timesCompleted: Int

    public init(stars: Int, bestAccuracy: Double, timesCompleted: Int) {
        self.stars = stars
        self.bestAccuracy = bestAccuracy
        self.timesCompleted = timesCompleted
    }
}

/// Toàn bộ tiến độ học của người dùng (lưu dạng JSON).
public struct UserProgress: Codable, Equatable {
    public var lessons: [String: LessonRecord] = [:]
    /// Điểm cao nhất (0...100) của từng bài hát.
    public var songBest: [String: Int] = [:]
    public var songStars: [String: Int] = [:]
    public var totalXP = 0
    /// XP theo ngày, khóa dạng "yyyy-MM-dd".
    public var xpByDay: [String: Int] = [:]
    public var streak = 0
    public var longestStreak = 0
    public var lastActiveDay: String?
    public var notesPlayed = 0
    public var practiceSeconds: Double = 0

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func isCompleted(_ lessonID: String) -> Bool { lessons[lessonID] != nil }
    public func stars(for lessonID: String) -> Int { lessons[lessonID]?.stars ?? 0 }

    public func xp(on date: Date, calendar: Calendar = .current) -> Int {
        xpByDay[UserProgress.dayKey(date, calendar: calendar)] ?? 0
    }

    /// Chuỗi ngày hiện tại (bằng 0 nếu hôm qua và hôm nay đều không học).
    public func currentStreak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let last = lastActiveDay else { return 0 }
        let today = UserProgress.dayKey(now, calendar: calendar)
        guard let y = calendar.date(byAdding: .day, value: -1, to: now) else { return streak }
        let yesterday = UserProgress.dayKey(y, calendar: calendar)
        return (last == today || last == yesterday) ? streak : 0
    }

    /// Cộng XP và cập nhật chuỗi ngày học.
    public mutating func addXP(_ amount: Int, at date: Date = Date(), calendar: Calendar = .current) {
        guard amount > 0 else { return }
        totalXP += amount
        let today = UserProgress.dayKey(date, calendar: calendar)
        xpByDay[today, default: 0] += amount
        markActive(at: date, calendar: calendar)
    }

    public mutating func markActive(at date: Date = Date(), calendar: Calendar = .current) {
        let today = UserProgress.dayKey(date, calendar: calendar)
        if lastActiveDay == today { return }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date).map { UserProgress.dayKey($0, calendar: calendar) }
        if let last = lastActiveDay, last == yesterday {
            streak += 1
        } else {
            streak = 1
        }
        longestStreak = max(longestStreak, streak)
        lastActiveDay = today
    }

    public mutating func recordLesson(_ lessonID: String, summary: LessonSummary, at date: Date = Date(), calendar: Calendar = .current) {
        guard summary.passed else { return }
        var record = lessons[lessonID] ?? LessonRecord(stars: 0, bestAccuracy: 0, timesCompleted: 0)
        record.stars = max(record.stars, summary.stars)
        record.bestAccuracy = max(record.bestAccuracy, summary.accuracy)
        record.timesCompleted += 1
        lessons[lessonID] = record
        practiceSeconds += summary.duration
        addXP(summary.xp, at: date, calendar: calendar)
    }

    /// Ghi điểm bài hát, trả về số XP nhận được.
    @discardableResult
    public mutating func recordSong(_ songID: String, result: TimedResult, duration: TimeInterval,
                                    at date: Date = Date(), calendar: Calendar = .current) -> Int {
        let score = Int((result.score * 100).rounded())
        songBest[songID] = max(songBest[songID] ?? 0, score)
        songStars[songID] = max(songStars[songID] ?? 0, result.stars)
        practiceSeconds += duration
        let xp = result.stars == 0 ? 2 : 5 * result.stars
        addXP(xp, at: date, calendar: calendar)
        return xp
    }

    /// Mức (level) tính theo tổng XP, tăng dần độ khó.
    public var level: Int {
        var lvl = 1
        var need = 60
        var xp = totalXP
        while xp >= need {
            xp -= need
            lvl += 1
            need += 40
        }
        return lvl
    }
}
