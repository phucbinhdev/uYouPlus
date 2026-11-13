import PianoCore
import SwiftUI

/// Một nốt (hoặc hợp âm / dấu lặng) cần vẽ trên khuông.
struct StaffNote: Identifiable {
    let id: Int
    /// Vị trí ngang, đơn vị = khe khuông, tính từ gốc nội dung (sau khóa nhạc).
    var x: CGFloat
    var pitches: [Pitch]
    var duration: Double
    var color: Color = .duoText
    var label: String?
    var finger: Int?
    /// Tô nền nhạt phía sau (nốt hiện tại).
    var highlight = false

    var isRest: Bool { pitches.isEmpty }
}

/// Khuông nhạc 5 dòng, vẽ bằng ký hiệu SMuFL (Bravura).
struct StaffView: View {
    var clef: Clef
    var notes: [StaffNote]
    /// Vị trí vạch nhịp (đơn vị khe, cùng hệ toạ độ với `StaffNote.x`).
    var barlines: [CGFloat] = []
    /// Dịch nội dung sang trái (đơn vị khe) – dùng khi cuộn bản nhạc.
    var scroll: CGFloat = 0
    /// Vạch chạy (đơn vị khe, cùng hệ toạ độ với nốt, đã trừ `scroll`).
    var playhead: CGFloat?
    /// Căn giữa nội dung nếu vừa khung.
    var centerContent = false
    var showLabels = true

    var body: some View {
        Canvas { ctx, size in
            draw(&ctx, size: size)
        }
    }

    // MARK: Vẽ

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let s = size.height / 13 // một khe
        let top = s * 4.5
        let bottom = top + 4 * s
        func y(_ pos: Int) -> CGFloat { bottom - CGFloat(pos) * s / 2 }
        let lineColor = Color(hex: "9E9E9E")
        let clefArea = s * 3.6

        // Gốc nội dung
        var originX = clefArea + s * 1.6 - scroll * s
        if centerContent, let last = notes.map(\.x).max() {
            let contentWidth = (last + 2) * s
            let available = size.width - clefArea - s * 1.6
            if contentWidth < available {
                originX = clefArea + s * 1.6 + (available - contentWidth) / 2
            }
        }

        // 5 dòng kẻ
        for i in 0..<5 {
            var p = Path()
            let yy = top + CGFloat(i) * s
            p.move(to: CGPoint(x: s * 0.3, y: yy))
            p.addLine(to: CGPoint(x: size.width - s * 0.3, y: yy))
            ctx.stroke(p, with: .color(lineColor), lineWidth: max(1, s * 0.09))
        }
        // Vạch đầu khuông
        var startBar = Path()
        startBar.move(to: CGPoint(x: s * 0.3, y: top))
        startBar.addLine(to: CGPoint(x: s * 0.3, y: bottom))
        ctx.stroke(startBar, with: .color(lineColor), lineWidth: max(1, s * 0.12))

        // Khóa nhạc
        switch clef {
        case .treble:
            ctx.fill(glyph(.gClef, at: CGPoint(x: s * 0.8, y: y(2)), s), with: .color(.duoText))
        case .bass:
            ctx.fill(glyph(.fClef, at: CGPoint(x: s * 0.8, y: y(6)), s), with: .color(.duoText))
        }

        // Phần nội dung bị cắt ở vùng khóa nhạc.
        var content = ctx
        content.clip(to: Path(CGRect(x: clefArea, y: 0, width: size.width - clefArea, height: size.height)))

        for bx in barlines {
            let x = originX + bx * s
            guard x > clefArea - s, x < size.width + s else { continue }
            var p = Path()
            p.move(to: CGPoint(x: x, y: top))
            p.addLine(to: CGPoint(x: x, y: bottom))
            content.stroke(p, with: .color(lineColor), lineWidth: max(1, s * 0.12))
        }

        if let ph = playhead {
            let x = originX + ph * s
            let r = CGRect(x: x - s * 0.15, y: top - s * 3, width: s * 0.3, height: s * 10)
            content.fill(Path(roundedRect: r, cornerRadius: s * 0.15), with: .color(Color.duoBlue.opacity(0.55)))
        }

        for note in notes {
            let x = originX + note.x * s
            guard x > clefArea - s * 3, x < size.width + s * 2 else { continue }
            drawNote(note, x: x, s: s, y: y, top: top, bottom: bottom, ctx: &content)
        }
    }

    private func drawNote(_ note: StaffNote, x: CGFloat, s: CGFloat, y: (Int) -> CGFloat,
                          top: CGFloat, bottom: CGFloat, ctx: inout GraphicsContext) {
        let color = note.color
        if note.highlight {
            let r = CGRect(x: x - s * 0.7, y: top - s * 3.2, width: s * 2.6, height: s * 10.4)
            ctx.fill(Path(roundedRect: r, cornerRadius: s * 0.6), with: .color(Color.duoBlue.opacity(0.12)))
        }

        if note.isRest {
            let g = MusicGlyph.rest(forDuration: note.duration)
            let originY: CGFloat
            switch note.duration {
            case 4...: originY = y(6)
            default: originY = y(4)
            }
            ctx.fill(glyph(g, at: CGPoint(x: x, y: originY), s), with: .color(color.opacity(0.8)))
            return
        }

        let positions = note.pitches.map { $0.staffPosition(in: clef) }
        let head = MusicGlyph.notehead(forDuration: note.duration)
        let headW = CGFloat(head.advance) * s

        // Dòng kẻ phụ
        let minPos = positions.min() ?? 0
        let maxPos = positions.max() ?? 0
        var ledgers: [Int] = []
        if minPos <= -2 { ledgers += stride(from: -2, through: minPos, by: -2).map { $0 } }
        if maxPos >= 10 { ledgers += stride(from: 10, through: maxPos, by: 2).map { $0 } }
        for l in ledgers {
            var p = Path()
            p.move(to: CGPoint(x: x - s * 0.4, y: y(l)))
            p.addLine(to: CGPoint(x: x + headW + s * 0.4, y: y(l)))
            ctx.stroke(p, with: .color(Color(hex: "9E9E9E")), lineWidth: max(1, s * 0.12))
        }

        // Đầu nốt và dấu hóa
        for (i, pitch) in note.pitches.enumerated() {
            let pos = positions[i]
            ctx.fill(glyph(head, at: CGPoint(x: x, y: y(pos)), s), with: .color(color))
            let acc: MusicGlyph?
            switch pitch.accidental {
            case .sharp: acc = .sharp
            case .flat: acc = .flat
            case .natural: acc = nil
            }
            if let acc = acc {
                let ax = x - (CGFloat(acc.advance) + 0.25) * s
                ctx.fill(glyph(acc, at: CGPoint(x: ax, y: y(pos)), s), with: .color(color))
            }
            if MusicGlyph.isDotted(note.duration) {
                let dotPos = pos % 2 == 0 ? pos + 1 : pos
                ctx.fill(glyph(.dot, at: CGPoint(x: x + headW + s * 0.3, y: y(dotPos)), s), with: .color(color))
            }
        }

        // Cán nốt và đuôi móc
        if note.duration < 4 {
            let avg = Double(positions.reduce(0, +)) / Double(max(1, positions.count))
            let stemUp = avg < 4
            let stemW = s * 0.12
            let flags = MusicGlyph.flagCount(note.duration)
            if stemUp {
                let sx = x + headW - stemW
                let y1 = y(minPos) - s * 0.15
                let y2 = min(y(maxPos) - s * 3.5, y(4))
                ctx.fill(Path(CGRect(x: sx, y: y2, width: stemW, height: y1 - y2)), with: .color(color))
                if flags > 0 {
                    let g: MusicGlyph = flags == 1 ? .flag8thUp : .flag16thUp
                    ctx.fill(glyph(g, at: CGPoint(x: sx, y: y2), s), with: .color(color))
                }
            } else {
                let sx = x
                let y1 = y(maxPos) + s * 0.15
                let y2 = max(y(minPos) + s * 3.5, y(4))
                ctx.fill(Path(CGRect(x: sx, y: y1, width: stemW, height: y2 - y1)), with: .color(color))
                if flags > 0 {
                    let g: MusicGlyph = flags == 1 ? .flag8thDown : .flag16thDown
                    ctx.fill(glyph(g, at: CGPoint(x: sx, y: y2), s), with: .color(color))
                }
            }
        }

        // Tên nốt dưới khuông
        if showLabels, let label = note.label {
            let labelY = max(bottom + s * 3.4, y(minPos) + s * 1.6)
            ctx.draw(Text(label).font(.system(size: s * 1.05, weight: .heavy, design: .rounded)).foregroundColor(color),
                     at: CGPoint(x: x + headW / 2, y: labelY), anchor: .center)
        }
        // Số ngón tay trên khuông
        if let finger = note.finger {
            let fy = min(top - s * 2.6, y(maxPos) - s * 4.2)
            let d = s * 1.5
            let circle = Path(ellipseIn: CGRect(x: x + headW / 2 - d / 2, y: fy - d / 2, width: d, height: d))
            ctx.fill(circle, with: .color(.duoOrange))
            ctx.draw(Text("\(finger)").font(.system(size: s * 1.0, weight: .heavy, design: .rounded)).foregroundColor(.white),
                     at: CGPoint(x: x + headW / 2, y: fy), anchor: .center)
        }
    }

    private func glyph(_ g: MusicGlyph, at origin: CGPoint, _ scale: CGFloat) -> Path {
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y + CGFloat(y) * scale)
        }
        for c in g.commands {
            switch c {
            case .move(let x, let y): p.move(to: pt(x, y))
            case .line(let x, let y): p.addLine(to: pt(x, y))
            case .quad(let x1, let y1, let x, let y): p.addQuadCurve(to: pt(x, y), control: pt(x1, y1))
            case .cubic(let x1, let y1, let x2, let y2, let x, let y):
                p.addCurve(to: pt(x, y), control1: pt(x1, y1), control2: pt(x2, y2))
            case .close: p.closeSubpath()
            }
        }
        return p
    }
}

extension StaffView: Animatable {
    /// Cho phép cuộn mượt khuông nhạc bằng `withAnimation`.
    var animatableData: CGFloat {
        get { scroll }
        set { scroll = newValue }
    }
}

extension StaffNote {
    /// Bố trí đều các nốt của một đoạn nhạc ngắn (dùng trong bài tập).
    static func layout(_ notes: [ScoreNote], spacing: CGFloat = 3.2, colors: (Int) -> Color = { _ in .duoText },
                       label: (ScoreNote) -> String? = { _ in nil }, showFingers: Bool = true, highlight: Int? = nil) -> [StaffNote] {
        notes.enumerated().map { i, n in
            StaffNote(id: i, x: CGFloat(i) * spacing, pitches: n.pitches, duration: n.duration, color: colors(i),
                      label: label(n), finger: showFingers ? n.finger : nil, highlight: i == highlight)
        }
    }
}
