import XCTest
@testable import PianoCore

/// Bộ sinh số ngẫu nhiên cố định để kiểm thử.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class PitchTests: XCTestCase {
    func testParsingNames() {
        XCTAssertEqual(Pitch(name: "C4")?.midi, 60)
        XCTAssertEqual(Pitch(name: "A4")?.midi, 69)
        XCTAssertEqual(Pitch(name: "F#4")?.midi, 66)
        XCTAssertEqual(Pitch(name: "Bb3")?.midi, 58)
        XCTAssertEqual(Pitch(name: "C-1")?.midi, 0)
        XCTAssertNil(Pitch(name: "H4"))
        XCTAssertNil(Pitch(name: "C"))
    }

    func testNames() {
        XCTAssertEqual(P("C4").name(.solfege), "Đô")
        XCTAssertEqual(P("G4").name(.letter), "G")
        XCTAssertEqual(P("E4").name(.both), "Mi (E)")
        XCTAssertEqual(P("F#4").name(.solfege), "Fa♯")
        XCTAssertEqual(P("Bb4").name(.letter), "B♭")
        XCTAssertEqual(P("C5").name(.letter, withOctave: true), "C5")
        XCTAssertEqual(P("Bb4"), P("A#4"), "Hai cách viết của cùng một phím phải bằng nhau")
    }

    func testStaffPositions() {
        XCTAssertEqual(P("E4").staffPosition(in: .treble), 0)
        XCTAssertEqual(P("F5").staffPosition(in: .treble), 8)
        XCTAssertEqual(P("C4").staffPosition(in: .treble), -2)
        XCTAssertEqual(P("G2").staffPosition(in: .bass), 0)
        XCTAssertEqual(P("A3").staffPosition(in: .bass), 8)
        XCTAssertEqual(P("F3").staffPosition(in: .bass), 6)
        XCTAssertEqual(P("F#4").staffPosition(in: .treble), P("F4").staffPosition(in: .treble))
        XCTAssertEqual(P("Bb4").staffPosition(in: .treble), P("B4").staffPosition(in: .treble))
    }

    func testOctaveAndColor() {
        XCTAssertEqual(P("C4").octave, 4)
        XCTAssertEqual(P("B3").octave, 3)
        XCTAssertTrue(P("C#4").isBlack)
        XCTAssertFalse(P("E4").isBlack)
        XCTAssertEqual(P("A4").frequency, 440, accuracy: 0.001)
    }

    func testKeyboardRange() {
        XCTAssertEqual(keyboardRange(for: [P("C4"), P("G4")]), 48...72)
        XCTAssertEqual(keyboardRange(for: [P("C3"), P("G3")]), 48...72)
        XCTAssertEqual(keyboardRange(for: [P("C4"), P("G5")]), 60...84)
        let r = keyboardRange(for: [P("E5")])
        XCTAssertTrue(r.contains(76))
        XCTAssertEqual(r.lowerBound % 12, 0)
    }

    func testClefChoice() {
        XCTAssertEqual(Clef.best(for: [P("C3"), P("E3")]), .bass)
        XCTAssertEqual(Clef.best(for: [P("C4"), P("E4")]), .treble)
    }
}

final class ScoreParserTests: XCTestCase {
    func testDurationsAndBeats() throws {
        let notes = try ScoreParser.parse("C4 D4:h | E4:q. F4:e R:w G4+B4+D5:w@1")
        XCTAssertEqual(notes.map(\.duration), [1, 2, 1.5, 0.5, 4, 4])
        XCTAssertEqual(notes.map(\.beat), [0, 1, 3, 4.5, 5, 9])
        XCTAssertTrue(notes[4].isRest)
        XCTAssertEqual(notes[5].pitches, [P("G4"), P("B4"), P("D5")])
        XCTAssertEqual(notes[5].finger, 1)
    }

    func testFingerAfterDuration() throws {
        let notes = try ScoreParser.parse("C4:h@5 E4@3")
        XCTAssertEqual(notes[0].finger, 5)
        XCTAssertEqual(notes[0].duration, 2)
        XCTAssertEqual(notes[1].finger, 3)
    }

    func testInvalidTokens() {
        XCTAssertThrowsError(try ScoreParser.parse("C4:x"))
        XCTAssertThrowsError(try ScoreParser.parse("Q4"))
        XCTAssertThrowsError(try ScoreParser.parse("C4@9"))
    }

    func testAllSongsParseAndMeasuresAreWhole() {
        XCTAssertFalse(SongLibrary.all.isEmpty)
        var ids = Set<String>()
        for song in SongLibrary.all {
            XCTAssertTrue(ids.insert(song.id).inserted, "Trùng id: \(song.id)")
            XCTAssertFalse(song.playableNotes.isEmpty, song.id)
            // Tổng số phách sau ô lấy đà phải chia hết cho số phách mỗi ô nhịp.
            let body = song.totalBeats - song.pickup
            let measures = body / song.beatsPerMeasure
            XCTAssertEqual(measures, measures.rounded(), accuracy: 0.001, "Bài \(song.id) có ô nhịp lẻ (\(body) phách)")
        }
    }
}

final class StepEvaluatorTests: XCTestCase {
    func testSingleNoteCorrect() {
        let ev = StepEvaluator(steps: [[P("E4")]], mode: .exact)
        let fb = ev.noteOn(P("E4"))
        XCTAssertEqual(fb?.isCorrect, true)
        XCTAssertEqual(fb?.outcome?.success, true)
        XCTAssertEqual(fb?.outcome?.mistakes, 0)
    }

    func testWrongThenRight() {
        let ev = StepEvaluator(steps: [[P("E4")]], mode: .exact)
        XCTAssertEqual(ev.noteOn(P("D4"))?.isCorrect, false)
        ev.noteOff(P("D4"))
        XCTAssertNil(ev.noteOn(P("E5"))?.outcome, "Sai quãng tám ở chế độ chính xác")
        let fb = ev.noteOn(P("E4"))
        XCTAssertEqual(fb?.outcome?.success, false)
        XCTAssertEqual(ev.mistakes, 2)
    }

    func testPitchClassMode() {
        let ev = StepEvaluator(steps: [[P("C4")]], mode: .pitchClass)
        XCTAssertEqual(ev.noteOn(P("C6"))?.outcome?.success, true)
    }

    func testSequenceWithRepeatedNotes() {
        let notes = try! ScoreParser.parse("E4 E4 E4:h R D4")
        let ev = StepEvaluator(exercise: Exercise(.sequence(title: "", notes: notes)), strictOctave: true)
        XCTAssertEqual(ev.steps.count, 4)
        for p in ["E4", "E4", "E4"] {
            let fb = ev.noteOn(P(p))
            XCTAssertEqual(fb?.isCorrect, true)
            ev.noteOff(P(p))
        }
        XCTAssertEqual(ev.stepIndex, 3)
        XCTAssertEqual(ev.noteOn(P("D4"))?.outcome?.success, true)
    }

    func testSequenceAllowsFewMistakes() {
        let steps = "C4 D4 E4 F4 G4 A4 B4 C5 D5 E5".split(separator: " ").map { [P(String($0))] }
        let ev = StepEvaluator(steps: steps, mode: .exact, allowedMistakes: 2)
        ev.noteOn(P("C#4"))
        ev.noteOn(P("C#4"))
        var last: NoteFeedback?
        for s in steps { last = ev.noteOn(s[0]) }
        XCTAssertEqual(last?.outcome?.success, true)
        XCTAssertEqual(last?.outcome?.mistakes, 2)
        XCTAssertEqual(last?.outcome?.accuracy ?? 0, 10.0 / 12.0, accuracy: 0.0001)
    }

    func testChordMustBeHeldTogether() {
        let ev = StepEvaluator(steps: [[P("C4"), P("E4"), P("G4")]], mode: .exact, allowedMistakes: 1)
        ev.noteOn(P("C4"))
        ev.noteOff(P("C4"))
        ev.noteOn(P("E4"))
        XCTAssertNil(ev.noteOn(P("G4"))?.outcome, "Đô đã được thả nên hợp âm chưa đủ")
        let fb = ev.noteOn(P("C4"))
        XCTAssertEqual(fb?.outcome?.success, true)
    }

    func testChordWrongNote() {
        let ev = StepEvaluator(exercise: Exercise(.chord(name: "C", pitches: [P("C4"), P("E4"), P("G4")])), strictOctave: true)
        XCTAssertEqual(ev.noteOn(P("F4"))?.isCorrect, false)
        ev.noteOff(P("F4"))
        ev.noteOn(P("C4")); ev.noteOn(P("E4"))
        let fb = ev.noteOn(P("G4"))
        XCTAssertEqual(fb?.outcome?.success, true, "Cho phép 1 lỗi với hợp âm")
    }

    func testIgnoresInputAfterFinish() {
        let ev = StepEvaluator(steps: [[P("C4")]], mode: .exact)
        ev.noteOn(P("C4"))
        XCTAssertNil(ev.noteOn(P("D4")))
        XCTAssertEqual(ev.mistakes, 0)
    }
}

final class TimedTrackerTests: XCTestCase {
    func testPerfectGoodMissAndWrong() throws {
        let notes = try ScoreParser.parse("C4 D4 E4 F4")
        let tracker = TimedNoteTracker(notes: notes, secondsPerBeat: 1, mode: .exact)
        XCTAssertEqual(tracker.noteOn(P("C4"), at: 0.02)?.grade, .perfect)
        XCTAssertEqual(tracker.noteOn(P("D4"), at: 1.2)?.grade, .good)
        XCTAssertNil(tracker.noteOn(P("G4"), at: 2.0), "Sai cao độ")
        XCTAssertEqual(tracker.expire(before: 2.5).count, 1, "Mi bị trượt")
        XCTAssertNil(tracker.noteOn(P("F4"), at: 3.5), "Quá muộn")
        let result = tracker.finish()
        XCTAssertEqual(result.perfect, 1)
        XCTAssertEqual(result.good, 1)
        XCTAssertEqual(result.miss, 2)
        XCTAssertEqual(result.wrong, 2)
        XCTAssertEqual(result.total, 4)
    }

    func testAllPerfectGivesThreeStars() throws {
        let notes = try ScoreParser.parse("C4 C4 C4 C4")
        let tracker = TimedNoteTracker(notes: notes, secondsPerBeat: 0.5, mode: .exact)
        for i in 0..<4 { tracker.noteOn(P("C4"), at: Double(i) * 0.5 + 0.01) }
        let r = tracker.finish()
        XCTAssertEqual(r.perfect, 4)
        XCTAssertEqual(r.stars, 3)
        XCTAssertEqual(r.score, 1)
        XCTAssertTrue(r.outcome.success)
    }

    func testChordTargets() throws {
        let notes = try ScoreParser.parse("C4+E4+G4:w")
        let tracker = TimedNoteTracker(notes: notes, secondsPerBeat: 1, mode: .exact)
        XCTAssertEqual(tracker.targets.count, 3)
        tracker.noteOn(P("C4"), at: 0)
        tracker.noteOn(P("E4"), at: 0.01)
        tracker.noteOn(P("G4"), at: 0.02)
        XCTAssertTrue(tracker.isComplete)
    }

    func testRhythmAnyKey() {
        let pattern = RhythmPattern(score: "C4 C4 R C4", tempo: 60)
        let tracker = TimedNoteTracker(rhythm: pattern)
        XCTAssertEqual(tracker.targets.count, 3)
        XCTAssertNotNil(tracker.noteOn(P("A2"), at: 0))
        XCTAssertNotNil(tracker.noteOn(P("G5"), at: 1.05))
        XCTAssertNil(tracker.noteOn(P("G5"), at: 2.0), "Đánh vào dấu lặng là thừa")
        XCTAssertNotNil(tracker.noteOn(P("C4"), at: 3.0))
        let r = tracker.finish()
        XCTAssertEqual(r.miss, 0)
        XCTAssertEqual(r.wrong, 1)
    }
}

final class LessonSessionTests: XCTestCase {
    func makeExercises(_ n: Int) -> [Exercise] {
        (0..<n).map { _ in Exercise(.findKey(P("C4"), prompt: .name)) }
    }

    func testPerfectLesson() {
        var s = LessonSession(exercises: makeExercises(4))
        while !s.isFinished { s.record(success: true) }
        let sum = s.summary(duration: 60)
        XCTAssertTrue(sum.passed)
        XCTAssertTrue(sum.perfect)
        XCTAssertEqual(sum.stars, 3)
        XCTAssertEqual(sum.xp, 15)
        XCTAssertEqual(s.progress, 1)
    }

    func testFailedExerciseIsRequeued() {
        var s = LessonSession(exercises: makeExercises(2))
        let first = s.current!.id
        s.record(success: false, mistakes: 1)
        XCTAssertEqual(s.hearts, 4)
        XCTAssertEqual(s.queue.count, 3)
        XCTAssertEqual(s.queue.last?.id, first)
        XCTAssertEqual(s.progress, 0)
        s.record(success: true)
        XCTAssertEqual(s.progress, 0.5)
        s.record(success: true)
        XCTAssertTrue(s.isFinished)
        let sum = s.summary(duration: 10)
        XCTAssertTrue(sum.passed)
        XCTAssertFalse(sum.perfect)
        XCTAssertEqual(sum.accuracy, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(sum.stars, 1)
    }

    func testRunningOutOfHearts() {
        var s = LessonSession(exercises: makeExercises(3), hearts: 2)
        s.record(success: false)
        s.record(success: false)
        XCTAssertTrue(s.isFailed)
        XCTAssertTrue(s.isFinished)
        let sum = s.summary(duration: 5)
        XCTAssertFalse(sum.passed)
        XCTAssertEqual(sum.xp, 0)
    }

    func testUnlimitedHearts() {
        var s = LessonSession(exercises: makeExercises(1), hearts: 1, unlimitedHearts: true)
        s.record(success: false)
        s.record(success: false)
        XCTAssertFalse(s.isFailed)
        s.record(success: true)
        XCTAssertTrue(s.isFinished)
        XCTAssertTrue(s.summary(duration: 1).passed)
    }

    func testIntroductionsAreNotGraded() {
        var s = LessonSession(exercises: [Exercise(.introduce(P("C4"), tip: ""))])
        s.record(success: false, mistakes: 3)
        XCTAssertEqual(s.hearts, LessonSession.defaultHearts)
        XCTAssertTrue(s.isFinished)
        XCTAssertTrue(s.summary(duration: 1).perfect)
    }
}

final class CurriculumTests: XCTestCase {
    func testLessonIDsUniqueAndExercisesGenerated() {
        var ids = Set<String>()
        var rng = SeededRNG(state: 42)
        for lesson in Curriculum.allLessons {
            XCTAssertTrue(ids.insert(lesson.id).inserted, "Trùng id: \(lesson.id)")
            let exercises = lesson.makeExercises(using: &rng)
            XCTAssertGreaterThanOrEqual(exercises.count, 3, lesson.id)
            for ex in exercises {
                switch ex.kind {
                case .sequence(_, let notes):
                    XCTAssertFalse(notes.isEmpty, "Chuỗi nốt rỗng trong \(lesson.id)")
                case .rhythm(let pattern):
                    XCTAssertFalse(pattern.onsets.isEmpty, lesson.id)
                case .theory(_, let choices, let answer, _):
                    XCTAssertTrue(choices.indices.contains(answer), lesson.id)
                    XCTAssertEqual(Set(choices).count, choices.count, "Đáp án trùng trong \(lesson.id)")
                case .nameQuiz(let p, let choices):
                    XCTAssertTrue(choices.contains(p), lesson.id)
                    XCTAssertEqual(choices.count, 4, lesson.id)
                    XCTAssertEqual(Set(choices.map { $0.letterName() }).count, 4, "Tên đáp án trùng trong \(lesson.id)")
                case .chord(_, let pitches):
                    XCTAssertGreaterThanOrEqual(pitches.count, 3, lesson.id)
                default:
                    break
                }
            }
        }
        XCTAssertGreaterThan(ids.count, 30)
    }

    func testTheoryAnswersAreShuffled() {
        var rng = SeededRNG(state: 7)
        let lesson = Curriculum.lesson(id: "u1l6")!
        var positions = Set<Int>()
        for _ in 0..<20 {
            for ex in lesson.makeExercises(using: &rng) {
                if case .theory(_, _, let answer, _) = ex.kind { positions.insert(answer) }
            }
        }
        XCTAssertGreaterThan(positions.count, 1)
    }

    func testUnlocking() {
        var progress = UserProgress()
        let lessons = Curriculum.allLessons
        XCTAssertTrue(Curriculum.isUnlocked(lessons[0].id, progress: progress))
        XCTAssertFalse(Curriculum.isUnlocked(lessons[1].id, progress: progress))
        progress.lessons[lessons[0].id] = LessonRecord(stars: 3, bestAccuracy: 1, timesCompleted: 1)
        XCTAssertTrue(Curriculum.isUnlocked(lessons[1].id, progress: progress))
        XCTAssertEqual(Curriculum.nextLesson(progress: progress)?.id, lessons[1].id)
    }
}

final class ProgressTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testStreak() {
        var p = UserProgress()
        p.addXP(10, at: date(2026, 1, 1), calendar: calendar)
        p.addXP(10, at: date(2026, 1, 1, 20), calendar: calendar)
        XCTAssertEqual(p.streak, 1)
        p.addXP(10, at: date(2026, 1, 2), calendar: calendar)
        XCTAssertEqual(p.streak, 2)
        XCTAssertEqual(p.currentStreak(now: date(2026, 1, 3), calendar: calendar), 2)
        XCTAssertEqual(p.currentStreak(now: date(2026, 1, 4), calendar: calendar), 0)
        p.addXP(10, at: date(2026, 1, 5), calendar: calendar)
        XCTAssertEqual(p.streak, 1)
        XCTAssertEqual(p.longestStreak, 2)
        XCTAssertEqual(p.totalXP, 40)
        XCTAssertEqual(p.xp(on: date(2026, 1, 1), calendar: calendar), 20)
    }

    func testRecordLessonKeepsBest() {
        var p = UserProgress()
        let good = LessonSummary(xp: 15, accuracy: 1, stars: 3, mistakes: 0, duration: 30, passed: true, perfect: true)
        let worse = LessonSummary(xp: 10, accuracy: 0.7, stars: 1, mistakes: 3, duration: 30, passed: true, perfect: false)
        let failed = LessonSummary(xp: 0, accuracy: 0.2, stars: 0, mistakes: 9, duration: 30, passed: false, perfect: false)
        p.recordLesson("a", summary: good, at: date(2026, 2, 1), calendar: calendar)
        p.recordLesson("a", summary: worse, at: date(2026, 2, 1), calendar: calendar)
        p.recordLesson("b", summary: failed, at: date(2026, 2, 1), calendar: calendar)
        XCTAssertEqual(p.lessons["a"]?.stars, 3)
        XCTAssertEqual(p.lessons["a"]?.timesCompleted, 2)
        XCTAssertNil(p.lessons["b"])
        XCTAssertEqual(p.totalXP, 25)
    }

    func testCodableRoundTrip() throws {
        var p = UserProgress()
        p.addXP(30)
        p.songBest["mary"] = 88
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(UserProgress.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func testLevels() {
        var p = UserProgress()
        XCTAssertEqual(p.level, 1)
        p.totalXP = 60
        XCTAssertEqual(p.level, 2)
        p.totalXP = 60 + 100
        XCTAssertEqual(p.level, 3)
    }
}

final class TheoryTests: XCTestCase {
    func testChordDetection() {
        XCTAssertEqual(ChordDetector.detect([60, 64, 67])?.symbol, "C")
        XCTAssertEqual(ChordDetector.detect([57, 60, 64])?.symbol, "Am")
        XCTAssertEqual(ChordDetector.detect([64, 67, 72])?.symbol, "C/E")
        XCTAssertEqual(ChordDetector.detect([55, 59, 62, 65])?.symbol, "G7")
        XCTAssertEqual(ChordDetector.detect([60, 64, 67], naming: .solfege)?.vietnameseName, "Đô trưởng")
        XCTAssertNil(ChordDetector.detect([60]))
        XCTAssertNil(ChordDetector.detect([60, 61, 62]))
    }

    func testMIDIByteParser() {
        var parser = MIDIByteParser()
        // Note on, running status note on, note on vel 0 (= off), realtime byte giữa chừng, CC64
        let msgs = parser.parse([0x90, 60, 100, 64, 90, 0xF8, 60, 0, 0xB0, 64, 127, 0x80, 64, 0])
        XCTAssertEqual(msgs, [
            .noteOn(note: 60, velocity: 100, channel: 0),
            .noteOn(note: 64, velocity: 90, channel: 0),
            .noteOff(note: 60, channel: 0),
            .controlChange(controller: 64, value: 127, channel: 0),
            .noteOff(note: 64, channel: 0)
        ])
    }

    func testMIDIParserSkipsSysEx() {
        var parser = MIDIByteParser()
        let msgs = parser.parse([0xF0, 0x7E, 0x01, 0x90, 0xF7, 0x91, 62, 50])
        XCTAssertEqual(msgs, [.noteOn(note: 62, velocity: 50, channel: 1)])
    }

    func testUMPDecoding() {
        // MT=2, group 0, status 0x93, note 60, vel 100
        let word: UInt32 = 0x2093_3C64
        XCTAssertEqual(MIDIByteParser.decodeUMP(word), .noteOn(note: 60, velocity: 100, channel: 3))
        XCTAssertNil(MIDIByteParser.decodeUMP(0x4093_3C64))
    }

    func testUMPMultiWordPacketsAreSkipped() {
        // SysEx 7-bit (MT=3, 2 từ) có từ thứ hai trông giống MIDI 1.0, sau đó là một note on thật.
        let words: [UInt32] = [0x3016_7E01, 0x2090_3C64, 0x2090_4050]
        XCTAssertEqual(MIDIByteParser.decodeUMPWords(words), [.noteOn(note: 64, velocity: 80, channel: 0)])
    }
}

final class GlyphTests: XCTestCase {
    func testPathParser() {
        let cmds = SVGPathParser.parse("M1 2 L3-4 H5 V6 C1 1 2 2 3 3 Q4 4 5 5 Z")
        XCTAssertEqual(cmds, [.move(1, 2), .line(3, -4), .line(5, -4), .line(5, 6),
                              .cubic(1, 1, 2, 2, 3, 3), .quad(4, 4, 5, 5), .close])
    }

    func testGlyphsParsed() {
        let all: [MusicGlyph] = [.gClef, .fClef, .noteheadBlack, .noteheadHalf, .noteheadWhole, .restWhole, .restHalf,
                                 .restQuarter, .rest8th, .rest16th, .flag8thUp, .flag8thDown, .flag16thUp, .flag16thDown,
                                 .sharp, .flat, .natural, .dot]
        for g in all {
            XCTAssertGreaterThan(g.commands.count, 2)
            XCTAssertGreaterThan(g.advance, 0)
        }
        // Khóa Sol kéo dài khoảng 7 khe, gốc nằm trên dòng Sol.
        let b = SVGPathParser.bounds(MusicGlyph.gClef.commands)!
        XCTAssertLessThan(b.minY, -3.5)
        XCTAssertGreaterThan(b.maxY, 1.5)
        // Đầu nốt cao đúng 1 khe.
        let n = SVGPathParser.bounds(MusicGlyph.noteheadBlack.commands)!
        XCTAssertEqual(n.maxY - n.minY, 1, accuracy: 0.05)
    }

    func testDurationsToGlyphs() {
        XCTAssertEqual(MusicGlyph.flagCount(0.5), 1)
        XCTAssertEqual(MusicGlyph.flagCount(0.75), 1)
        XCTAssertEqual(MusicGlyph.flagCount(0.25), 2)
        XCTAssertEqual(MusicGlyph.flagCount(1.5), 0)
        XCTAssertTrue(MusicGlyph.isDotted(3))
        XCTAssertFalse(MusicGlyph.isDotted(2))
    }
}
