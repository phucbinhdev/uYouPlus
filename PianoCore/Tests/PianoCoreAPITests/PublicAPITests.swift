import Foundation
import PianoCore
import XCTest

/// Dùng `import` thường (không `@testable`): đảm bảo mọi API mà ứng dụng iPad gọi tới đều là `public`.
final class PublicAPITests: XCTestCase {
    func testAppFacingAPIIsPublic() {
        // Gọi mọi API của PianoCore mà ứng dụng sử dụng, với import thường (không @testable).
        let naming: NoteNaming = .solfege
        for n in NoteNaming.allCases { _ = (n.id, n.displayName) }
        let p = Pitch(60)
        let p2 = Pitch(61, prefersFlat: true)
        _ = (p.name(naming), p.name(naming, withOctave: true), p.shortName(naming), p.letterName(), p.solfegeName(),
             p.pitchClass, p.midi, p.isBlack, p.accidental, p.staffPosition(in: .treble), p.octave, Pitch.middleC, P("B4"), p2)
        switch p.accidental { case .sharp, .flat, .natural: break }
        _ = Clef.best(for: [p]); _ = keyboardRange(for: [p])
        let sn = ScoreNote(pitches: [p], beat: 0, duration: 4)
        _ = (sn.pitches, sn.beat, sn.duration, sn.finger, sn.isRest, sn.endBeat)
        for s in SongLibrary.all { _ = (s.id, s.title, s.subtitle, s.level, s.tempo, s.beatsPerMeasure, s.pickup, s.clef, s.notes, s.allPitches, s.totalBeats, s.barlineBeats) }
        _ = SongLibrary.song(id: "mary")
        let lesson = Curriculum.allLessons[0]
        _ = (lesson.id, lesson.title, lesson.subtitle, lesson.icon, lesson.kind == .review, lesson.baseXP)
        let exs = lesson.makeExercises()
        for e in exs {
          _ = (e.kind, e.title(naming), e.isGraded, e.showHints, e.involvedPitches, e.matchMode(strictOctave: false), e.id)
          switch e.kind {
          case .introduce(let a, let t): _ = (a, t)
          case .findKey(let a, let st): switch st { case .name, .staff, .nameAndStaff: _ = a }
          case .nameQuiz(let a, let c): _ = (a, c)
          case .earTraining(let a, let r): _ = (a, r)
          case .sequence(let t, let n): _ = (t, n)
          case .chord(let n, let ps): _ = (n, ps)
          case .rhythm(let r): _ = (r.notes, r.totalBeats, r.secondsPerBeat, r.countInBeats, r.beatsPerMeasure)
          case .theory(let q, let c, let a, let x): _ = (q, c, a, x)
          }
        }
        let ev = StepEvaluator(exercise: exs[0], strictOctave: false)
        let ev2 = StepEvaluator(steps: [[p]], mode: .pitchClass)
        if let fb = ev2.noteOn(p) { _ = (fb.isCorrect, fb.completedStep, fb.outcome?.success, fb.outcome?.mistakes) }
        ev2.noteOff(p)
        _ = (ev.steps, ev.stepIndex, ev.remainingInStep, ev.mistakes)
        let tr = TimedNoteTracker(rhythm: RhythmPattern(score: "C4 C4"))
        let tr2 = TimedNoteTracker(notes: [sn], secondsPerBeat: 0.5, mode: .exact)
        if let hit = tr2.noteOn(p, at: 0) { _ = (hit.target, hit.grade == .perfect) }
        for i in tr.expire(before: 1) { _ = (tr.targets[i].noteIndex, tr.targets[i].time, tr.targets[i].grade, tr.targets[i].pitch?.midi) }
        let r = TimedResult(perfect: 1, good: 0, miss: 0, wrong: 0)
        _ = (r.score, r.stars, r.outcome.success, r.total, r.perfect, r.good, r.miss, r.wrong, tr.finish())
        var session = LessonSession(exercises: exs, unlimitedHearts: false, baseXP: lesson.baseXP)
        _ = (session.current, session.position, session.progress, session.hearts, session.isFinished)
        session.record(success: true, mistakes: 0)
        let sum = LessonSummary(xp: 1, accuracy: 1, stars: 3, mistakes: 0, duration: 1, passed: true, perfect: true)
        _ = (session.summary(duration: 1), sum.xp, sum.accuracy, sum.stars, sum.duration, sum.passed, sum.perfect)
        for u in Curriculum.units { _ = (u.id, u.title, u.description, u.colorHex, u.lessons) }
        _ = (Curriculum.lesson(id: "u1l1"), Curriculum.unit(containing: "u1l1")?.colorHex)
        var prog = UserProgress()
        _ = (Curriculum.isUnlocked("u1l1", progress: prog), Curriculum.nextLesson(progress: prog))
        prog.recordLesson("u1l1", summary: sum)
        _ = prog.recordSong("mary", result: r, duration: 3)
        prog.lessons["x"] = LessonRecord(stars: 1, bestAccuracy: 0, timesCompleted: 0)
        prog.practiceSeconds += 1; prog.notesPlayed += 1; prog.songBest["a"] = 1; prog.songStars["a"] = 1
        _ = (prog.xp(on: Date()), prog.currentStreak(), prog.longestStreak, prog.totalXP, prog.level, prog.isCompleted("x"), prog.stars(for: "x"),
             prog.lessons.values.map { $0.stars })
        if let c = ChordDetector.detect([60, 64, 67], naming: naming) { _ = (c.symbol, c.vietnameseName, c.isInversion) }
        _ = ChordDetector.intervalName(3)
        for m in MIDIByteParser.decodeUMPWords([0x2090_3C64]) {
          switch m {
          case .noteOn(let n, let v, _): _ = (n, v)
          case .noteOff(let n, _): _ = n
          case .controlChange(let c, let v, _): _ = (c, v)
          default: break
          }
        }
        let glyphs: [MusicGlyph] = [.gClef, .fClef, .sharp, .flat, .dot, .flag8thUp, .flag8thDown, .flag16thUp, .flag16thDown,
                                    MusicGlyph.rest(forDuration: 1), MusicGlyph.notehead(forDuration: 1)]
        for g in glyphs {
          _ = g.advance
          for c in g.commands {
            switch c { case .move(let x, let y), .line(let x, let y): _ = (x, y)
            case .quad(let a, let b, let x, let y): _ = (a, b, x, y)
            case .cubic(let a, let b, let c2, let d, let x, let y): _ = (a, b, c2, d, x, y)
            case .close: break }
          }
        }
        _ = (MusicGlyph.isDotted(1.5), MusicGlyph.flagCount(0.5))
        let grade: TimingGrade = .good; switch grade { case .perfect, .good, .miss: break }
    }
}
