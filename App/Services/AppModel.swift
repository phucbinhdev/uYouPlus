import Foundation
import PianoCore
import SwiftUI

/// Cài đặt người dùng.
struct AppSettings: Codable, Equatable {
    var naming: NoteNaming = .solfege
    /// Hiện tên nốt dưới khuông nhạc.
    var showNoteNames = true
    /// Hiện tên nốt trên phím đàn ảo.
    var showKeyLabels = true
    /// Hiện số ngón tay gợi ý.
    var showFingers = true
    /// Bắt buộc đánh đúng quãng tám.
    var strictOctave = false
    /// Không bị mất tim khi sai.
    var unlimitedHearts = false
    /// Phát âm thanh trên iPad khi đánh bằng đàn thật (đàn thường đã tự phát tiếng).
    var soundForMIDI = false
    /// Âm thanh đúng/sai.
    var soundEffects = true
    /// Mục tiêu XP mỗi ngày.
    var dailyGoalXP = 30
    /// Tự kết nối lại đàn Bluetooth đã dùng lần trước.
    var autoReconnect = true
    /// Mã định danh thiết bị Bluetooth MIDI đã kết nối gần nhất.
    var lastPeripheralID: String?
    var lastPeripheralName: String?
    /// Âm lượng bộ tổng hợp âm thanh 0...1
    var volume: Double = 0.8
    var hasSeenOnboarding = false

    init() {}

    // Giải mã an toàn: thiếu khóa thì dùng giá trị mặc định (tương thích khi thêm cài đặt mới).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        naming = (try? c.decode(NoteNaming.self, forKey: .naming)) ?? d.naming
        showNoteNames = (try? c.decode(Bool.self, forKey: .showNoteNames)) ?? d.showNoteNames
        showKeyLabels = (try? c.decode(Bool.self, forKey: .showKeyLabels)) ?? d.showKeyLabels
        showFingers = (try? c.decode(Bool.self, forKey: .showFingers)) ?? d.showFingers
        strictOctave = (try? c.decode(Bool.self, forKey: .strictOctave)) ?? d.strictOctave
        unlimitedHearts = (try? c.decode(Bool.self, forKey: .unlimitedHearts)) ?? d.unlimitedHearts
        soundForMIDI = (try? c.decode(Bool.self, forKey: .soundForMIDI)) ?? d.soundForMIDI
        soundEffects = (try? c.decode(Bool.self, forKey: .soundEffects)) ?? d.soundEffects
        dailyGoalXP = (try? c.decode(Int.self, forKey: .dailyGoalXP)) ?? d.dailyGoalXP
        autoReconnect = (try? c.decode(Bool.self, forKey: .autoReconnect)) ?? d.autoReconnect
        lastPeripheralID = try? c.decode(String.self, forKey: .lastPeripheralID)
        lastPeripheralName = try? c.decode(String.self, forKey: .lastPeripheralName)
        volume = (try? c.decode(Double.self, forKey: .volume)) ?? d.volume
        hasSeenOnboarding = (try? c.decode(Bool.self, forKey: .hasSeenOnboarding)) ?? d.hasSeenOnboarding
    }
}

/// Lưu trữ tiến độ học và cài đặt.
final class AppModel: ObservableObject {
    @Published var progress: UserProgress {
        didSet { save(progress, key: Keys.progress) }
    }
    @Published var settings: AppSettings {
        didSet { save(settings, key: Keys.settings) }
    }

    private enum Keys {
        static let progress = "pianogo.progress.v1"
        static let settings = "pianogo.settings.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = AppModel.load(UserProgress.self, key: Keys.progress, defaults: defaults) ?? UserProgress()
        settings = AppModel.load(AppSettings.self, key: Keys.settings, defaults: defaults) ?? AppSettings()
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Tiện ích

    var naming: NoteNaming { settings.naming }
    var todayXP: Int { progress.xp(on: Date()) }
    var streak: Int { progress.currentStreak() }
    var dailyGoalReached: Bool { todayXP >= settings.dailyGoalXP }

    func recordLesson(_ lesson: Lesson, summary: LessonSummary) {
        progress.recordLesson(lesson.id, summary: summary)
    }

    @discardableResult
    func recordSong(_ song: Song, result: TimedResult, duration: TimeInterval) -> Int {
        progress.recordSong(song.id, result: result, duration: duration)
    }

    func addPracticeTime(_ seconds: TimeInterval, notes: Int) {
        guard seconds > 1 || notes > 0 else { return }
        progress.practiceSeconds += seconds
        progress.notesPlayed += notes
    }

    func resetProgress() {
        progress = UserProgress()
    }

    /// Mở khóa toàn bộ bài học (dành cho người đã biết chơi).
    func unlockAll() {
        var p = progress
        for lesson in Curriculum.allLessons where p.lessons[lesson.id] == nil {
            p.lessons[lesson.id] = LessonRecord(stars: 1, bestAccuracy: 0, timesCompleted: 0)
        }
        progress = p
    }
}
