import Foundation
import PianoCore

/// Tham số khởi chạy dùng để chụp màn hình tự động trên trình giả lập (CI).
/// Ví dụ: `-PGShot 1 -PGTab 1`, `-PGLesson u1l2 -PGSkip 1`, `-PGSong mary`, `-PGConnect 1`, `-PGDemo 1`.
/// Khi chạy bình thường không có tham số nào nên không ảnh hưởng tới người dùng.
enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    static var isScreenshotMode: Bool { defaults.string(forKey: "PGShot") != nil }
    static var tab: Int? { defaults.string(forKey: "PGTab").flatMap(Int.init) }
    static var lessonID: String? { defaults.string(forKey: "PGLesson") }
    static var skipExercises: Int { defaults.string(forKey: "PGSkip").flatMap(Int.init) ?? 0 }
    static var songID: String? { defaults.string(forKey: "PGSong") }
    static var openConnect: Bool { defaults.string(forKey: "PGConnect") != nil }
    static var seedDemoProgress: Bool { defaults.string(forKey: "PGDemo") != nil }

    /// Tạo tiến độ mẫu để ảnh chụp lộ trình học trông giống thực tế.
    static func applyDemoProgress(to app: AppModel) {
        guard seedDemoProgress else { return }
        var p = UserProgress()
        let cal = Calendar.current
        for (i, lesson) in Curriculum.allLessons.prefix(8).enumerated() {
            let summary = LessonSummary(xp: 15, accuracy: 0.9, stars: i % 3 == 1 ? 2 : 3, mistakes: 1,
                                        duration: 180, passed: true, perfect: i % 3 != 1)
            let day = cal.date(byAdding: .day, value: -(7 - i), to: Date()) ?? Date()
            p.recordLesson(lesson.id, summary: summary, at: day)
        }
        p.songBest["mary"] = 92
        p.songStars["mary"] = 3
        p.songBest["twinkle"] = 78
        p.songStars["twinkle"] = 2
        app.progress = p
        app.settings.hasSeenOnboarding = true
    }
}
