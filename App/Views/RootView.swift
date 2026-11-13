import PianoCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var input: NoteInput
    @EnvironmentObject private var midi: MIDIManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var showConnect = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            LearnPathView(showConnect: $showConnect)
                .tabItem { Label("Học", systemImage: "house.fill") }
                .tag(0)
            SongsView(showConnect: $showConnect)
                .tabItem { Label("Bài hát", systemImage: "music.note.list") }
                .tag(1)
            FreePlayView(showConnect: $showConnect)
                .tabItem { Label("Chơi tự do", systemImage: "pianokeys") }
                .tag(2)
            ProfileView(showConnect: $showConnect)
                .tabItem { Label("Hồ sơ", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .accentColor(.duoGreen)
        .sheet(isPresented: $showConnect) {
            ConnectView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                app.settings.hasSeenOnboarding = true
                showOnboarding = false
            } onConnect: {
                app.settings.hasSeenOnboarding = true
                showOnboarding = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showConnect = true }
            }
        }
        .onAppear {
            LaunchOptions.applyDemoProgress(to: app)
            if let t = LaunchOptions.tab { tab = t }
            if LaunchOptions.openConnect {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showConnect = true }
            }
            let screenshot = LaunchOptions.isScreenshotMode && LaunchOptions.tab != nil
            if !app.settings.hasSeenOnboarding && !screenshot && LaunchOptions.lessonID == nil && LaunchOptions.songID == nil {
                showOnboarding = true
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                midi.refresh()
            } else {
                app.addPracticeTime(0, notes: input.takeNotesPlayed())
            }
        }
    }
}

/// Thanh trạng thái trên cùng: đàn, chuỗi ngày, XP.
struct StatusBar: View {
    @Binding var showConnect: Bool
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var midi: MIDIManager

    var body: some View {
        HStack(spacing: 18) {
            Button {
                showConnect = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 18, weight: .bold))
                    Text(midi.isConnected ? (midi.connectedName ?? "Đã kết nối") : "Kết nối đàn")
                        .font(.rounded(15, .heavy))
                        .lineLimit(1)
                }
                .foregroundColor(midi.isConnected ? Color(hex: "58A700") : .duoBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(midi.isConnected ? Color.duoGreenLight : Color.duoBlueLight))
            }
            Spacer()
            Label {
                Text("\(app.streak)")
            } icon: {
                Image(systemName: "flame.fill")
            }
            .foregroundColor(app.streak > 0 ? .duoOrange : .duoGrayDark)
            Label {
                Text("\(app.progress.totalXP)")
            } icon: {
                Image(systemName: "bolt.fill")
            }
            .foregroundColor(Color.duoYellow.darker(0.05))
            Label {
                Text("Cấp \(app.progress.level)")
            } icon: {
                Image(systemName: "crown.fill")
            }
            .foregroundColor(.duoPurple)
        }
        .font(.rounded(18, .heavy))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(Rectangle().fill(Color.duoGray).frame(height: 2), alignment: .bottom)
    }
}

/// Chào mừng lần đầu mở ứng dụng.
struct OnboardingView: View {
    var onSkip: () -> Void
    var onConnect: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            MascotView(mood: .excited, size: 170)
            Text("Chào mừng đến với Piano Go!")
                .font(.rounded(36, .heavy))
                .foregroundColor(.duoText)
                .multilineTextAlignment(.center)
            Text("Học đàn piano mỗi ngày qua những bài học ngắn, vui như chơi game. Kết nối iPad với đàn Bora BX20 qua Bluetooth để ứng dụng nghe được bạn đánh và chấm điểm ngay lập tức.")
                .font(.rounded(19, .semibold))
                .foregroundColor(.duoSubtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            VStack(alignment: .leading, spacing: 14) {
                feature("pianokeys", .duoBlue, "Kết nối đàn qua Bluetooth MIDI hoặc dùng bàn phím trên màn hình")
                feature("map.fill", .duoGreen, "8 chương, 44 bài học từ cơ bản đến nâng cao")
                feature("music.note.list", .duoPurple, "Luyện bài hát với chế độ chờ và chế độ theo nhịp")
                feature("flame.fill", .duoOrange, "XP, chuỗi ngày học và ngôi sao cho mỗi bài")
            }
            .frame(maxWidth: 560)
            Spacer()
            VStack(spacing: 12) {
                Button("Kết nối đàn ngay", action: onConnect)
                    .buttonStyle(DuoButtonStyle(color: .duoGreen))
                Button("Để sau, dùng bàn phím trên màn hình", action: onSkip)
                    .font(.rounded(16, .heavy))
                    .foregroundColor(.duoBlue)
            }
            .frame(maxWidth: 480)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 28)
    }

    private func feature(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(color))
            Text(text)
                .font(.rounded(17, .bold))
                .foregroundColor(.duoText)
        }
    }
}
