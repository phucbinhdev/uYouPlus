import PianoCore
import SwiftUI

/// Lộ trình học kiểu Duolingo: các chương và bài học xếp thành đường zig-zag.
struct LearnPathView: View {
    @Binding var showConnect: Bool
    @EnvironmentObject private var app: AppModel
    @State private var selected: Lesson?
    @State private var activeLesson: Lesson?

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(showConnect: $showConnect)
            GeometryReader { geo in
                let wide = geo.size.width > 920
                HStack(alignment: .top, spacing: 28) {
                    path(compact: !wide)
                        .frame(maxWidth: 620)
                    if wide {
                        ScrollView {
                            SidePanel(showConnect: $showConnect)
                                .padding(.vertical, 24)
                        }
                        .frame(width: 340)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white)
        .overlay(previewOverlay)
        .fullScreenCover(item: $activeLesson) { lesson in
            LessonView(lesson: lesson, unlimitedHearts: app.settings.unlimitedHearts) {
                activeLesson = nil
            }
            .environmentObject(app)
        }
    }

    private func path(compact: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if compact {
                        DailyGoalCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                    ForEach(Array(Curriculum.units.enumerated()), id: \.element.id) { unitIndex, unit in
                        UnitHeader(unit: unit, index: unitIndex)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 12)
                        ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { i, lesson in
                            LessonNodeView(lesson: lesson, color: Color(hex: unit.colorHex), state: state(of: lesson)) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = lesson }
                            }
                            .offset(x: zigzag(i))
                            .padding(.vertical, 10)
                            .id(lesson.id)
                        }
                    }
                    VStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 54))
                            .foregroundColor(.duoYellow)
                        Text("Hoàn thành tất cả để trở thành nghệ sĩ piano!")
                            .font(.rounded(18, .bold))
                            .foregroundColor(.duoSubtext)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                    .padding(.bottom, 100)
                }
            }
            .onAppear {
                if let id = LaunchOptions.lessonID, activeLesson == nil, let lesson = Curriculum.lesson(id: id) {
                    activeLesson = lesson
                }
                if let next = Curriculum.nextLesson(progress: app.progress) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { proxy.scrollTo(next.id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func zigzag(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [0, 55, 85, 55, 0, -55, -85, -55]
        return pattern[i % pattern.count]
    }

    private func state(of lesson: Lesson) -> LessonNodeView.NodeState {
        if app.progress.isCompleted(lesson.id) { return .done(stars: app.progress.stars(for: lesson.id)) }
        if Curriculum.isUnlocked(lesson.id, progress: app.progress) { return .current }
        return .locked
    }

    @ViewBuilder private var previewOverlay: some View {
        if let lesson = selected {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { selected = nil } }
                LessonPreviewCard(lesson: lesson, state: state(of: lesson)) {
                    selected = nil
                    activeLesson = lesson
                } onClose: {
                    withAnimation { selected = nil }
                }
                .frame(maxWidth: 560)
                .padding(24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct UnitHeader: View {
    let unit: CourseUnit
    let index: Int

    var body: some View {
        let color = Color(hex: unit.colorHex)
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CHƯƠNG \(index + 1)")
                    .font(.rounded(15, .heavy))
                    .foregroundColor(.white.opacity(0.85))
                Text(unit.title)
                    .font(.rounded(24, .heavy))
                    .foregroundColor(.white)
                Text(unit.description)
                    .font(.rounded(16, .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(color.darker()).offset(y: 4)
                RoundedRectangle(cornerRadius: 18).fill(color)
            }
        )
    }
}

struct LessonNodeView: View {
    enum NodeState: Equatable {
        case locked
        case current
        case done(stars: Int)
    }

    let lesson: Lesson
    let color: Color
    let state: NodeState
    var onTap: () -> Void
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 6) {
            if state == .current {
                Text("BẮT ĐẦU")
                    .font(.rounded(15, .heavy))
                    .foregroundColor(color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12).stroke(Color.duoGray, lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    )
                    .offset(y: bounce ? -6 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bounce = true }
                    }
            }
            Button(action: onTap) {
                Image(systemName: state == .locked ? "lock.fill" : (isDone ? "checkmark" : lesson.icon))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(state == .locked ? .duoGrayDark : .white)
                    .frame(width: 80, height: 74)
            }
            .buttonStyle(NodeButtonStyle(color: fill, ring: state == .current ? color : nil))
            if case .done(let stars) = state {
                HStack(spacing: 2) {
                    ForEach(0..<3) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(i < stars ? .duoYellow : .duoGray)
                    }
                }
            }
            Text(lesson.title)
                .font(.rounded(14, .bold))
                .foregroundColor(state == .locked ? .duoGrayDark : .duoText)
                .lineLimit(1)
                .frame(maxWidth: 170)
        }
    }

    private var isDone: Bool {
        if case .done = state { return true }
        return false
    }

    private var fill: Color {
        switch state {
        case .locked: return .duoGray
        case .current: return color
        case .done: return lesson.kind == .review ? .duoYellow : color
        }
    }
}

/// Nút tròn nổi của bài học.
struct NodeButtonStyle: ButtonStyle {
    let color: Color
    var ring: Color?

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(
                ZStack {
                    Ellipse().fill(color.darker()).offset(y: 7)
                    Ellipse().fill(color).offset(y: pressed ? 7 : 0)
                }
            )
            .offset(y: pressed ? 3 : 0)
            .padding(.bottom, 7)
            .padding(8)
            .overlay(
                Group {
                    if let ring = ring {
                        Ellipse().stroke(ring.opacity(0.35), lineWidth: 7)
                    }
                }
            )
    }
}

/// Thẻ thông tin khi chọn một bài học.
struct LessonPreviewCard: View {
    let lesson: Lesson
    let state: LessonNodeView.NodeState
    var onStart: () -> Void
    var onClose: () -> Void

    var body: some View {
        let unit = Curriculum.unit(containing: lesson.id)
        let color = state == .locked ? Color.duoGrayDark : Color(hex: unit?.colorHex ?? "58CC02")
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(unit?.title.uppercased() ?? "")
                    .font(.rounded(14, .heavy))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            Text(lesson.title)
                .font(.rounded(26, .heavy))
                .foregroundColor(.white)
            Text(lesson.subtitle)
                .font(.rounded(18, .semibold))
                .foregroundColor(.white.opacity(0.92))
            if state == .locked {
                Text("Hãy hoàn thành các bài trước để mở khóa bài này.")
                    .font(.rounded(17, .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)
            } else {
                Button(action: onStart) {
                    Text(buttonTitle)
                }
                .buttonStyle(DuoButtonStyle(color: .white, textColor: color))
                .padding(.top, 8)
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 20).fill(color))
    }

    private var buttonTitle: String {
        switch state {
        case .done: return "Luyện lại +\(lesson.baseXP) XP"
        default: return "Bắt đầu +\(lesson.baseXP) XP"
        }
    }
}

/// Mục tiêu XP trong ngày.
struct DailyGoalCard: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let goal = max(1, app.settings.dailyGoalXP)
        let today = app.todayXP
        HStack(spacing: 16) {
            Image(systemName: app.dailyGoalReached ? "checkmark.seal.fill" : "target")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(app.dailyGoalReached ? .duoGreen : .duoOrange)
            VStack(alignment: .leading, spacing: 8) {
                Text(app.dailyGoalReached ? "Đã đạt mục tiêu hôm nay!" : "Mục tiêu hôm nay")
                    .font(.rounded(17, .heavy))
                    .foregroundColor(.duoText)
                HStack(spacing: 10) {
                    DuoProgressBar(value: Double(today) / Double(goal), color: .duoOrange, height: 14)
                    Text("\(min(today, goal))/\(goal) XP")
                        .font(.rounded(14, .bold))
                        .foregroundColor(.duoSubtext)
                        .fixedSize()
                }
            }
        }
        .card()
    }
}

/// Cột bên phải trên iPad màn hình ngang.
struct SidePanel: View {
    @Binding var showConnect: Bool
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var midi: MIDIManager

    var body: some View {
        VStack(spacing: 18) {
            DailyGoalCard()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(midi.isConnected ? .duoGreen : .duoBlue)
                    Text(midi.isConnected ? "Đàn đã kết nối" : "Chưa kết nối đàn")
                        .font(.rounded(18, .heavy))
                        .foregroundColor(.duoText)
                }
                Text(midi.isConnected
                     ? "Đang nhận nốt từ \(midi.connectedName ?? "đàn"). Hãy đánh thử một phím!"
                     : "Bật Bluetooth trên đàn Bora BX20 rồi kết nối để học với đàn thật.")
                    .font(.rounded(15, .semibold))
                    .foregroundColor(.duoSubtext)
                Button(midi.isConnected ? "Quản lý kết nối" : "Kết nối đàn") { showConnect = true }
                    .buttonStyle(DuoButtonStyle(color: midi.isConnected ? .duoGreen : .duoBlue, height: 44))
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "flame.fill").foregroundColor(.duoOrange)
                    Text("Chuỗi \(app.streak) ngày")
                }
                .font(.rounded(18, .heavy))
                .foregroundColor(.duoText)
                WeekStrip()
                Text("Học mỗi ngày để giữ chuỗi. Kỷ lục: \(app.progress.longestStreak) ngày.")
                    .font(.rounded(14, .semibold))
                    .foregroundColor(.duoSubtext)
            }
            .card()
        }
    }
}

/// 7 ngày gần nhất: ngày nào có học được tô lửa.
struct WeekStrip: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let cal = Calendar.current
        let days: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateFormat = "EEEEE"
            return f
        }()
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let active = app.progress.xp(on: d) > 0
                VStack(spacing: 4) {
                    Text(formatter.string(from: d))
                        .font(.rounded(12, .bold))
                        .foregroundColor(.duoGrayDark)
                    Image(systemName: active ? "flame.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(active ? .duoOrange : .duoGray)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
