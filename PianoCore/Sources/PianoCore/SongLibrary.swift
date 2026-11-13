import Foundation

/// Thư viện bài hát (đều là giai điệu thuộc phạm vi công cộng), viết cho tay phải.
public enum SongLibrary {
    public static let all: [Song] = [
        Song(id: "scale-c", title: "Gam Đô trưởng", subtitle: "Bài luyện ngón", level: 1, tempo: 80,
             score: "C4@1 D4@2 E4@3 F4@1 | G4@2 A4@3 B4@4 C5@5 | C5@5 B4@4 A4@3 G4@2 | F4@1 E4@3 D4@2 C4@1"),

        Song(id: "hot-cross-buns", title: "Bánh nóng", subtitle: "Hot Cross Buns – Dân ca Anh", level: 1, tempo: 90,
             score: "E4@3 D4@2 C4:h@1 | E4 D4 C4:h | C4:e@1 C4:e C4:e C4:e D4:e@2 D4:e D4:e D4:e | E4@3 D4 C4:h"),

        Song(id: "mary", title: "Mary có chú cừu non", subtitle: "Mary Had a Little Lamb – Dân ca Mỹ", level: 1, tempo: 100,
             score: "E4@3 D4@2 C4@1 D4 | E4 E4 E4:h | D4 D4 D4:h | E4 G4@5 G4:h | E4 D4 C4 D4 | E4 E4 E4 E4 | D4 D4 E4 D4 | C4:w"),

        Song(id: "ode-to-joy", title: "Khúc hoan ca", subtitle: "Ode to Joy – L. v. Beethoven", level: 1, tempo: 100,
             score: "E4@3 E4 F4@4 G4@5 | G4 F4 E4 D4@2 | C4@1 C4 D4 E4 | E4:q. D4:e D4:h | E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4:q. C4:e C4:h"),

        Song(id: "frere-jacques", title: "Kìa con bướm vàng", subtitle: "Giai điệu Frère Jacques – Dân ca Pháp", level: 1, tempo: 100,
             score: "C4 D4 E4 C4 | C4 D4 E4 C4 | E4 F4 G4:h | E4 F4 G4:h | G4:e A4:e G4:e F4:e E4 C4 | G4:e A4:e G4:e F4:e E4 C4 | C4 G3 C4:h | C4 G3 C4:h"),

        Song(id: "twinkle", title: "Ngôi sao lấp lánh", subtitle: "Twinkle Twinkle Little Star – Dân ca Pháp", level: 1, tempo: 100,
             score: """
             C4@1 C4 G4@5 G4 | A4 A4 G4:h | F4@4 F4 E4@3 E4 | D4@2 D4 C4:h@1 |
             G4 G4 F4 F4 | E4 E4 D4:h | G4 G4 F4 F4 | E4 E4 D4:h |
             C4 C4 G4 G4 | A4 A4 G4:h | F4 F4 E4 E4 | D4 D4 C4:h
             """),

        Song(id: "au-clair", title: "Dưới ánh trăng", subtitle: "Au clair de la lune – Dân ca Pháp", level: 2, tempo: 100,
             score: """
             C4 C4 C4 D4 | E4:h D4:h | C4 E4 D4 D4 | C4:w |
             C4 C4 C4 D4 | E4:h D4:h | C4 E4 D4 D4 | C4:w |
             D4 D4 D4 D4 | A3:h A3:h | D4 C4 B3 A3 | G3:w |
             C4 C4 C4 D4 | E4:h D4:h | C4 E4 D4 D4 | C4:w
             """),

        Song(id: "london-bridge", title: "Cầu London", subtitle: "London Bridge – Dân ca Anh", level: 2, tempo: 100,
             score: "G4:q. A4:e G4 F4 | E4 F4 G4:h | D4 E4 F4:h | E4 F4 G4:h | G4:q. A4:e G4 F4 | E4 F4 G4:h | D4:h G4:h | E4 C4:h."),

        Song(id: "old-macdonald", title: "Nông trại vui vẻ", subtitle: "Old MacDonald – Dân ca Mỹ", level: 2, tempo: 110,
             score: "G4 G4 G4 D4 | E4 E4 D4:h | B4 B4 A4 A4 | G4:h. D4 | G4 G4 G4 D4 | E4 E4 D4:h | B4 B4 A4 A4 | G4:w"),

        Song(id: "jingle-bells", title: "Jingle Bells", subtitle: "J. Pierpont", level: 2, tempo: 110,
             score: """
             E4 E4 E4:h | E4 E4 E4:h | E4 G4 C4:q. D4:e | E4:w |
             F4 F4 F4:q. F4:e | F4 E4 E4 E4:e E4:e | E4 D4 D4 E4 | D4:h G4:h |
             E4 E4 E4:h | E4 E4 E4:h | E4 G4 C4:q. D4:e | E4:w |
             F4 F4 F4 F4 | F4 E4 E4 E4:e E4:e | G4 G4 F4 D4 | C4:w
             """),

        Song(id: "happy-birthday", title: "Chúc mừng sinh nhật", subtitle: "Happy Birthday – M. & P. Hill", level: 2, tempo: 90,
             beatsPerMeasure: 3, pickup: 1,
             score: "G4:e. G4:s | A4 G4 C5 | B4:h G4:e. G4:s | A4 G4 D5 | C5:h G4:e. G4:s | G5 E5 C5 | B4 A4 F5:e. F5:s | E5 C5 D5 | C5:h."),

        Song(id: "canon", title: "Canon", subtitle: "J. Pachelbel (giản lược)", level: 3, tempo: 70,
             score: "E5:h D5:h | C5:h B4:h | A4:h G4:h | A4:h B4:h | E5 D5 C5 B4 | A4 G4 A4 B4 | C5 B4 A4 G4 | F4 E4 F4 D4 | C4:w"),

        Song(id: "fur-elise", title: "Für Elise", subtitle: "L. v. Beethoven (đoạn mở đầu)", level: 3, tempo: 60,
             beatsPerMeasure: 1.5, pickup: 0.5,
             score: """
             E5:s D#5:s | E5:s D#5:s E5:s B4:s D5:s C5:s | A4:e R:s C4:s E4:s A4:s | B4:e R:s E4:s G#4:s B4:s |
             C5:e R:s E4:s E5:s D#5:s | E5:s D#5:s E5:s B4:s D5:s C5:s | A4:e R:s C4:s E4:s A4:s | B4:e R:s E4:s C5:s B4:s | A4:q.
             """)
    ]

    public static func song(id: String) -> Song? { all.first { $0.id == id } }
}
