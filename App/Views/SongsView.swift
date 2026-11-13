import PianoCore
import SwiftUI

struct SongsView: View {
    @Binding var showConnect: Bool
    @EnvironmentObject private var app: AppModel
    @State private var playing: Song?

    private let columns = [GridItem(.adaptive(minimum: 270, maximum: 400), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(showConnect: $showConnect)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bài hát")
                        .font(.rounded(32, .heavy))
                        .foregroundColor(.duoText)
                    Text("Chọn một bài để luyện. Chế độ “Chờ” đợi bạn đánh đúng từng nốt; chế độ “Theo nhịp” chấm điểm độ chính xác về thời gian.")
                        .font(.rounded(17, .semibold))
                        .foregroundColor(.duoSubtext)
                    ForEach(1...3, id: \.self) { level in
                        let songs = SongLibrary.all.filter { $0.level == level }
                        if !songs.isEmpty {
                            Text(levelName(level))
                                .font(.rounded(20, .heavy))
                                .foregroundColor(levelColor(level))
                                .padding(.top, 10)
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(songs) { song in
                                    SongCard(song: song, best: app.progress.songBest[song.id],
                                             stars: app.progress.songStars[song.id] ?? 0,
                                             color: levelColor(level)) {
                                        playing = song
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white)
        .fullScreenCover(item: $playing) { song in
            SongPlayerView(song: song, strictOctave: app.settings.strictOctave) { playing = nil }
                .environmentObject(app)
        }
    }

    private func levelName(_ l: Int) -> String {
        switch l {
        case 1: return "Dễ"
        case 2: return "Trung bình"
        default: return "Khó"
        }
    }

    private func levelColor(_ l: Int) -> Color {
        switch l {
        case 1: return .duoGreen
        case 2: return .duoBlue
        default: return .duoPurple
        }
    }
}

struct SongCard: View {
    let song: Song
    let best: Int?
    let stars: Int
    let color: Color
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(color))
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.rounded(19, .heavy))
                        .foregroundColor(.duoText)
                        .lineLimit(1)
                    Text(song.subtitle)
                        .font(.rounded(14, .semibold))
                        .foregroundColor(.duoSubtext)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Image(systemName: "star.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(i < stars ? .duoYellow : .duoGray)
                        }
                        if let best = best {
                            Text("Cao nhất \(best)%")
                                .font(.rounded(13, .bold))
                                .foregroundColor(.duoGrayDark)
                                .padding(.leading, 6)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .foregroundColor(color)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DuoChoiceStyle())
    }
}
