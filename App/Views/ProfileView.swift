import PianoCore
import SwiftUI

struct ProfileView: View {
    @Binding var showConnect: Bool
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var synth: SynthEngine
    @State private var confirmReset = false
    @State private var confirmUnlock = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(showConnect: $showConnect)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statsGrid
                    weekChart
                    settingsSection
                    dataSection
                    about
                }
                .padding(24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white)
    }

    private var header: some View {
        HStack(spacing: 22) {
            MascotView(mood: .happy, size: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text("Học viên Piano Go")
                    .font(.rounded(30, .heavy))
                    .foregroundColor(.duoText)
                Text("Cấp \(app.progress.level) • \(app.progress.totalXP) XP")
                    .font(.rounded(18, .bold))
                    .foregroundColor(.duoSubtext)
                let done = Curriculum.allLessons.filter { app.progress.isCompleted($0.id) }.count
                DuoProgressBar(value: Double(done) / Double(Curriculum.allLessons.count), color: .duoGreen, height: 14)
                    .frame(maxWidth: 320)
                Text("Đã học \(done)/\(Curriculum.allLessons.count) bài")
                    .font(.rounded(15, .bold))
                    .foregroundColor(.duoGrayDark)
            }
        }
    }

    private var statsGrid: some View {
        let p = app.progress
        let stars = p.lessons.values.reduce(0) { $0 + $1.stars }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
            statBox("flame.fill", .duoOrange, "\(app.streak)", "Chuỗi ngày hiện tại")
            statBox("trophy.fill", .duoYellow, "\(p.longestStreak)", "Chuỗi dài nhất")
            statBox("bolt.fill", .duoYellow, "\(p.totalXP)", "Tổng XP")
            statBox("star.fill", .duoYellow, "\(stars)", "Ngôi sao bài học")
            statBox("clock.fill", .duoBlue, formatDuration(p.practiceSeconds), "Thời gian luyện tập")
            statBox("music.note.list", .duoPurple, "\(p.songBest.count)/\(SongLibrary.all.count)", "Bài hát đã chơi")
        }
    }

    private func statBox(_ icon: String, _ color: Color, _ value: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.rounded(22, .heavy)).foregroundColor(.duoText)
                Text(title).font(.rounded(14, .bold)).foregroundColor(.duoGrayDark)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }

    private var weekChart: some View {
        let cal = Calendar.current
        let days: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
        let values = days.map { app.progress.xp(on: $0) }
        let maxValue = max(app.settings.dailyGoalXP, values.max() ?? 0, 1)
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateFormat = "EEE"
            return f
        }()
        return VStack(alignment: .leading, spacing: 14) {
            Text("XP 7 ngày qua")
                .font(.rounded(20, .heavy))
                .foregroundColor(.duoText)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 6) {
                        Text("\(values[i])")
                            .font(.rounded(13, .bold))
                            .foregroundColor(.duoSubtext)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(values[i] >= app.settings.dailyGoalXP ? Color.duoGreen : Color.duoBlue)
                            .frame(height: max(6, 140 * CGFloat(values[i]) / CGFloat(maxValue)))
                        Text(formatter.string(from: d))
                            .font(.rounded(13, .bold))
                            .foregroundColor(.duoGrayDark)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 190, alignment: .bottom)
        }
        .card(padding: 18)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cài đặt")
                .font(.rounded(20, .heavy))
                .foregroundColor(.duoText)
            HStack {
                Text("Tên nốt")
                Spacer()
                Picker("Tên nốt", selection: $app.settings.naming) {
                    ForEach(NoteNaming.allCases) { n in Text(n.displayName).tag(n) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            HStack {
                Text("Mục tiêu mỗi ngày")
                Spacer()
                Picker("Mục tiêu", selection: $app.settings.dailyGoalXP) {
                    Text("10 XP").tag(10)
                    Text("20 XP").tag(20)
                    Text("30 XP").tag(30)
                    Text("50 XP").tag(50)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            Toggle("Hiện tên nốt dưới khuông nhạc", isOn: $app.settings.showNoteNames)
            Toggle("Hiện tên nốt trên phím đàn ảo", isOn: $app.settings.showKeyLabels)
            Toggle("Hiện số ngón tay gợi ý", isOn: $app.settings.showFingers)
            Toggle("Bắt buộc đánh đúng quãng tám", isOn: $app.settings.strictOctave)
            Toggle("Tim vô hạn (không bị mất tim khi sai)", isOn: $app.settings.unlimitedHearts)
            Toggle("Âm thanh đúng / sai", isOn: $app.settings.soundEffects)
            Toggle("Phát tiếng trên iPad khi đánh đàn thật", isOn: $app.settings.soundForMIDI)
            HStack {
                Image(systemName: "speaker.fill").foregroundColor(.duoGrayDark)
                Slider(value: $app.settings.volume, in: 0...1, onEditingChanged: { editing in
                    if !editing { synth.play(72, duration: 0.4) }
                })
                Image(systemName: "speaker.wave.3.fill").foregroundColor(.duoGrayDark)
            }
            .onChange(of: app.settings.volume) { v in synth.volume = Float(v) }
            Button {
                showConnect = true
            } label: {
                Label("Kết nối đàn Bluetooth", systemImage: "pianokeys")
            }
            .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 46))
        }
        .font(.rounded(17, .bold))
        .foregroundColor(.duoText)
        .toggleStyle(SwitchToggleStyle(tint: .duoGreen))
        .card(padding: 18)
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dữ liệu")
                .font(.rounded(20, .heavy))
                .foregroundColor(.duoText)
            Button("Mở khóa tất cả bài học") { confirmUnlock = true }
                .buttonStyle(DuoButtonStyle(color: .duoPurple, height: 46))
                .alert(isPresented: $confirmUnlock) {
                    Alert(title: Text("Mở khóa tất cả?"),
                          message: Text("Dành cho người đã biết chơi đàn và muốn học bài bất kỳ."),
                          primaryButton: .default(Text("Mở khóa"), action: app.unlockAll),
                          secondaryButton: .cancel(Text("Hủy")))
                }
            Button("Xóa toàn bộ tiến độ") { confirmReset = true }
                .buttonStyle(DuoButtonStyle(color: .duoRed, height: 46))
                .alert(isPresented: $confirmReset) {
                    Alert(title: Text("Xóa tiến độ?"),
                          message: Text("XP, chuỗi ngày và kết quả tất cả bài học sẽ bị xóa. Không thể hoàn tác."),
                          primaryButton: .destructive(Text("Xóa"), action: app.resetProgress),
                          secondaryButton: .cancel(Text("Hủy")))
                }
        }
        .card(padding: 18)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Piano Go 1.0")
                .font(.rounded(16, .heavy))
                .foregroundColor(.duoGrayDark)
            Text("Ký hiệu âm nhạc dựa trên font Bravura (SIL Open Font License). Các bài hát là giai điệu dân gian/cổ điển thuộc phạm vi công cộng.")
                .font(.rounded(13, .semibold))
                .foregroundColor(.duoGrayDark)
        }
    }
}
