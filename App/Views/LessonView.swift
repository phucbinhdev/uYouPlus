import Combine
import PianoCore
import SwiftUI

/// Kết quả một bài tập, gửi từ màn hình bài tập về bài học.
struct ExerciseResult {
    var success: Bool
    var mistakes: Int = 0
    /// Dòng chi tiết trên banner (đáp án đúng, giải thích...).
    var detail: String?
}

final class LessonModel: ObservableObject {
    let lesson: Lesson
    let unlimitedHearts: Bool
    @Published private(set) var session: LessonSession
    @Published private(set) var feedback: Feedback?
    @Published private(set) var summary: LessonSummary?
    private var startDate = Date()

    struct Feedback {
        var success: Bool
        var title: String
        var detail: String?
        var mistakes: Int
    }

    private static let praises = ["Tuyệt vời!", "Chính xác!", "Giỏi lắm!", "Hay quá!", "Xuất sắc!", "Đúng rồi!"]

    init(lesson: Lesson, unlimitedHearts: Bool) {
        self.lesson = lesson
        self.unlimitedHearts = unlimitedHearts
        session = LessonSession(exercises: lesson.makeExercises(), unlimitedHearts: unlimitedHearts, baseXP: lesson.baseXP)
    }

    func finishExercise(_ result: ExerciseResult) {
        guard feedback == nil, let current = session.current else { return }
        let success = result.success || !current.isGraded
        let detail: String?
        if success {
            detail = result.detail
        } else if let d = result.detail {
            detail = d
        } else if result.mistakes > 0 {
            detail = "Bạn đã bấm sai \(result.mistakes) lần. Bài này sẽ được làm lại sau."
        } else {
            detail = "Bài này sẽ được làm lại sau."
        }
        feedback = Feedback(success: success,
                            title: success ? LessonModel.praises.randomElement()! : "Chưa đúng rồi",
                            detail: detail,
                            mistakes: result.mistakes)
    }

    func continueTapped() {
        guard let fb = feedback else { return }
        session.record(success: fb.success, mistakes: fb.mistakes)
        feedback = nil
        if session.isFinished {
            summary = session.summary(duration: Date().timeIntervalSince(startDate))
        }
    }

    func restart() {
        session = LessonSession(exercises: lesson.makeExercises(), unlimitedHearts: unlimitedHearts, baseXP: lesson.baseXP)
        feedback = nil
        summary = nil
        startDate = Date()
    }
}

struct LessonView: View {
    let lesson: Lesson
    var onClose: () -> Void

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var synth: SynthEngine
    @StateObject private var model: LessonModel
    @State private var confirmQuit = false

    init(lesson: Lesson, unlimitedHearts: Bool, onClose: @escaping () -> Void) {
        self.lesson = lesson
        self.onClose = onClose
        _model = StateObject(wrappedValue: LessonModel(lesson: lesson, unlimitedHearts: unlimitedHearts))
    }

    private var unitColor: Color {
        Color(hex: Curriculum.unit(containing: lesson.id)?.colorHex ?? "58CC02")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()
            if let summary = model.summary {
                LessonCompleteView(summary: summary, lesson: lesson, color: unitColor,
                                   onContinue: onClose,
                                   onRetry: { model.restart() })
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    topBar
                    if let exercise = model.session.current {
                        ExerciseHost(exercise: exercise, isActive: model.feedback == nil) { result in
                            model.finishExercise(result)
                        }
                        .id(model.session.position)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
                    }
                }
                if let fb = model.feedback {
                    FeedbackBanner(feedback: fb) {
                        withAnimation(.easeInOut(duration: 0.25)) { model.continueTapped() }
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.feedback?.title)
        .onChange(of: model.feedback?.success) { success in
            guard let success = success else { return }
            if app.settings.soundEffects { synth.playEffect(success ? .correct : .wrong) }
            success ? Haptics.success() : Haptics.error()
        }
        .onChange(of: model.summary) { summary in
            guard let summary = summary else { return }
            if summary.passed {
                app.recordLesson(lesson, summary: summary)
            }
            if app.settings.soundEffects { synth.playEffect(summary.passed ? .complete : .fail) }
        }
        .alert(isPresented: $confirmQuit) {
            Alert(title: Text("Thoát bài học?"),
                  message: Text("Tiến độ của bài học này sẽ không được lưu."),
                  primaryButton: .destructive(Text("Thoát"), action: onClose),
                  secondaryButton: .cancel(Text("Học tiếp")))
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                if model.session.progress > 0 { confirmQuit = true } else { onClose() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.duoGrayDark)
                    .frame(width: 44, height: 44)
            }
            DuoProgressBar(value: model.session.progress, color: unitColor)
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.duoRed)
                if model.unlimitedHearts {
                    Image(systemName: "infinity").foregroundColor(.duoRed).font(.rounded(18, .heavy))
                } else {
                    Text("\(model.session.hearts)")
                        .foregroundColor(.duoRed)
                        .font(.rounded(20, .heavy))
                }
            }
            .font(.system(size: 22))
            ConnectionDot()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// Chấm nhỏ cho biết đàn đã kết nối.
struct ConnectionDot: View {
    @EnvironmentObject private var midi: MIDIManager

    var body: some View {
        Image(systemName: "pianokeys")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(midi.isConnected ? .duoGreen : .duoGrayDark)
            .overlay(
                Circle().fill(midi.isConnected ? Color.duoGreen : Color.duoRed)
                    .frame(width: 8, height: 8)
                    .offset(x: 4, y: -4),
                alignment: .topTrailing
            )
            .accessibilityLabel(midi.isConnected ? "Đã kết nối đàn" : "Chưa kết nối đàn")
    }
}

/// Banner đúng / sai ở cuối màn hình, kèm nút Tiếp tục.
struct FeedbackBanner: View {
    let feedback: LessonModel.Feedback
    var onContinue: () -> Void

    var body: some View {
        let color: Color = feedback.success ? .duoGreen : .duoRed
        let textColor: Color = feedback.success ? Color(hex: "58A700") : Color(hex: "EA2B2B")
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: feedback.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(color)
                    .background(Circle().fill(Color.white).padding(4))
                Text(feedback.title)
                    .font(.rounded(26, .heavy))
                    .foregroundColor(textColor)
            }
            if let detail = feedback.detail {
                Text(detail)
                    .font(.rounded(18, .semibold))
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(feedback.success ? "Tiếp tục" : "Đã hiểu", action: onContinue)
                .buttonStyle(DuoButtonStyle(color: color))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((feedback.success ? Color.duoGreenLight : Color.duoRedLight).ignoresSafeArea(edges: .bottom))
    }
}

/// Màn hình kết thúc bài học.
struct LessonCompleteView: View {
    let summary: LessonSummary
    let lesson: Lesson
    let color: Color
    var onContinue: () -> Void
    var onRetry: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            if summary.passed { ConfettiView().allowsHitTesting(false) }
            VStack(spacing: 26) {
                Spacer()
                MascotView(mood: summary.passed ? .excited : .sad, size: 150)
                    .scaleEffect(appear ? 1 : 0.4)
                Text(summary.passed ? (summary.perfect ? "Hoàn hảo!" : "Hoàn thành bài học!") : "Hết tim rồi!")
                    .font(.rounded(36, .heavy))
                    .foregroundColor(summary.passed ? Color.duoYellow.darker(0.1) : Color.duoRed)
                Text(summary.passed ? lesson.title : "Đừng lo, luyện tập thêm một chút rồi thử lại nhé.")
                    .font(.rounded(20, .semibold))
                    .foregroundColor(.duoSubtext)
                    .multilineTextAlignment(.center)
                if summary.passed {
                    HStack(spacing: 10) {
                        ForEach(0..<3) { i in
                            Image(systemName: i < summary.stars ? "star.fill" : "star")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(i < summary.stars ? .duoYellow : .duoGray)
                                .scaleEffect(appear ? 1 : 0.1)
                                .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.3 + Double(i) * 0.15), value: appear)
                        }
                    }
                    HStack(spacing: 16) {
                        StatTile(title: "Tổng XP", value: "+\(summary.xp)", color: .duoYellow, icon: "bolt.fill")
                        StatTile(title: "Chính xác", value: "\(Int((summary.accuracy * 100).rounded()))%", color: .duoGreen, icon: "scope")
                        StatTile(title: "Thời gian", value: formatDuration(summary.duration), color: .duoBlue, icon: "clock.fill")
                    }
                    .frame(maxWidth: 560)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button(summary.passed ? "Tiếp tục" : "Thử lại") {
                        summary.passed ? onContinue() : onRetry()
                    }
                    .buttonStyle(DuoButtonStyle(color: summary.passed ? .duoGreen : .duoBlue))
                    if summary.passed {
                        Button("Học lại bài này", action: onRetry)
                            .font(.rounded(16, .heavy))
                            .foregroundColor(.duoBlue)
                    } else {
                        Button("Thoát", action: onContinue)
                            .font(.rounded(16, .heavy))
                            .foregroundColor(.duoGrayDark)
                    }
                }
                .frame(maxWidth: 480)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(.rounded(13, .heavy))
                .foregroundColor(.white)
                .padding(.vertical, 6)
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(value)
            }
            .font(.rounded(22, .heavy))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .padding([.horizontal, .bottom], 2)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(color))
    }
}

/// Hiệu ứng pháo giấy đơn giản.
struct ConfettiView: View {
    private struct Piece {
        let x: CGFloat
        let speed: CGFloat
        let size: CGFloat
        let color: Color
        let spin: Double
        let delay: Double
    }

    private let pieces: [Piece] = (0..<70).map { _ in
        Piece(x: .random(in: 0...1), speed: .random(in: 0.18...0.4), size: .random(in: 8...16),
              color: [Color.duoGreen, .duoBlue, .duoYellow, .duoRed, .duoPurple, .duoOrange].randomElement()!,
              spin: .random(in: 1...4), delay: .random(in: 0...1.2))
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let progress = CGFloat(max(0, t - p.delay)) * p.speed
                    guard progress < 1.3 else { continue }
                    let y = -20 + progress * (size.height + 40)
                    let x = p.x * size.width + sin(CGFloat(t) * 2 + p.x * 10) * 20
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * p.spin))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(p.color))
                }
            }
        }
        .ignoresSafeArea()
    }
}
