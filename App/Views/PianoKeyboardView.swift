import PianoCore
import SwiftUI
import UIKit

/// Bàn phím piano trên màn hình: hỗ trợ đa chạm (đánh hợp âm) và vuốt (glissando).
struct PianoKeyboardView: UIViewRepresentable {
    var range: ClosedRange<Int>
    /// Phím đang được giữ (từ đàn thật hoặc màn hình).
    var pressed: Set<Int>
    /// Màu phản hồi (đúng/sai) – ưu tiên cao nhất.
    var keyColors: [Int: Color] = [:]
    /// Phím gợi ý.
    var hints: [Int: Color] = [:]
    var naming: NoteNaming = .solfege
    /// Hiện tên trên mọi phím trắng (nếu không chỉ hiện ở phím Đô).
    var labelAllKeys = true
    var fingers: [Int: Int] = [:]
    var onNoteOn: (Int) -> Void
    var onNoteOff: (Int) -> Void

    func makeUIView(context: Context) -> PianoKeyboardUIView {
        let view = PianoKeyboardUIView()
        update(view)
        return view
    }

    func updateUIView(_ view: PianoKeyboardUIView, context: Context) {
        update(view)
    }

    private func update(_ view: PianoKeyboardUIView) {
        view.range = range
        view.pressed = pressed
        view.keyColors = keyColors.mapValues { UIColor($0) }
        view.hints = hints.mapValues { UIColor($0) }
        view.naming = naming
        view.labelAllKeys = labelAllKeys
        view.fingers = fingers
        view.onNoteOn = onNoteOn
        view.onNoteOff = onNoteOff
        view.setNeedsDisplay()
    }
}

final class PianoKeyboardUIView: UIView {
    var range: ClosedRange<Int> = 48...72
    var pressed: Set<Int> = []
    var keyColors: [Int: UIColor] = [:]
    var hints: [Int: UIColor] = [:]
    var naming: NoteNaming = .solfege
    var labelAllKeys = true
    var fingers: [Int: Int] = [:]
    var onNoteOn: ((Int) -> Void)?
    var onNoteOff: ((Int) -> Void)?

    private var touchNotes: [ObjectIdentifier: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Hình học

    private var whiteKeys: [Int] { range.filter { !Pitch($0).isBlack } }
    private var whiteWidth: CGFloat { bounds.width / CGFloat(max(1, whiteKeys.count)) }
    private var blackWidth: CGFloat { whiteWidth * 0.6 }
    private var blackHeight: CGFloat { bounds.height * 0.62 }

    func keyRect(_ midi: Int) -> CGRect {
        let whites = whiteKeys
        if !Pitch(midi).isBlack {
            let idx = whites.firstIndex(of: midi) ?? 0
            return CGRect(x: CGFloat(idx) * whiteWidth, y: 0, width: whiteWidth, height: bounds.height)
        }
        // Phím đen nằm giữa phím trắng bên dưới và phím trắng tiếp theo.
        let lowerWhite = midi - 1
        let idx = whites.firstIndex(of: lowerWhite) ?? -1
        let x = CGFloat(idx + 1) * whiteWidth - blackWidth / 2
        return CGRect(x: x, y: 0, width: blackWidth, height: blackHeight)
    }

    func note(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        if point.y <= blackHeight {
            for midi in range where Pitch(midi).isBlack && keyRect(midi).contains(point) {
                return midi
            }
        }
        for midi in whiteKeys where keyRect(midi).contains(point) {
            return midi
        }
        return nil
    }

    // MARK: Vẽ

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let radius = min(10, whiteWidth * 0.18)

        for midi in whiteKeys {
            let r = keyRect(midi).insetBy(dx: 1, dy: 0)
            let path = UIBezierPath(roundedRect: r, byRoundingCorners: [.bottomLeft, .bottomRight],
                                    cornerRadii: CGSize(width: radius, height: radius))
            let isPressed = pressed.contains(midi)
            var fill = UIColor.white
            if let hint = hints[midi] { fill = hint.withAlphaComponent(0.35) }
            if isPressed { fill = UIColor(white: 0.86, alpha: 1) }
            if let c = keyColors[midi] { fill = c }
            // Bóng dưới (độ dày phím)
            let shadow = UIBezierPath(roundedRect: r.offsetBy(dx: 0, dy: 0), byRoundingCorners: [.bottomLeft, .bottomRight],
                                      cornerRadii: CGSize(width: radius, height: radius))
            UIColor(white: 0.8, alpha: 1).setFill()
            shadow.fill()
            let face = UIBezierPath(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - (isPressed ? 2 : 6)),
                                    byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: radius, height: radius))
            fill.setFill()
            face.fill()
            UIColor(white: 0.78, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()

            if let hint = hints[midi], keyColors[midi] == nil {
                drawDot(center: CGPoint(x: r.midX, y: r.maxY - 46), color: hint)
            }
            drawLabel(for: midi, in: r, color: keyColors[midi] != nil ? .white : UIColor(white: 0.45, alpha: 1))
        }

        for midi in range where Pitch(midi).isBlack {
            let r = keyRect(midi)
            let isPressed = pressed.contains(midi)
            var fill = UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)
            if let hint = hints[midi] { fill = hint }
            if isPressed { fill = UIColor(white: 0.38, alpha: 1) }
            if let c = keyColors[midi] { fill = c }
            let body = UIBezierPath(roundedRect: r, byRoundingCorners: [.bottomLeft, .bottomRight],
                                    cornerRadii: CGSize(width: radius * 0.6, height: radius * 0.6))
            UIColor.black.setFill()
            body.fill()
            let face = UIBezierPath(roundedRect: CGRect(x: r.minX + 2, y: r.minY, width: r.width - 4, height: r.height - (isPressed ? 3 : 7)),
                                    byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: radius * 0.5, height: radius * 0.5))
            fill.setFill()
            face.fill()
            if let finger = fingers[midi] {
                drawFinger(finger, center: CGPoint(x: r.midX, y: r.maxY - 22), dark: false)
            }
        }
        ctx.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor)
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: 0, y: 1.5))
        ctx.addLine(to: CGPoint(x: bounds.width, y: 1.5))
        ctx.strokePath()
    }

    private func drawDot(center: CGPoint, color: UIColor) {
        let d: CGFloat = min(16, whiteWidth * 0.35)
        let dot = UIBezierPath(ovalIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
        color.setFill()
        dot.fill()
    }

    private func drawLabel(for midi: Int, in r: CGRect, color: UIColor) {
        let pitch = Pitch(midi)
        let isC = pitch.pitchClass == 0
        if let finger = fingers[midi] {
            drawFinger(finger, center: CGPoint(x: r.midX, y: r.maxY - 72), dark: true)
        }
        guard labelAllKeys || isC else { return }
        var text = pitch.shortName(naming)
        if isC { text += "\(pitch.octave)" }
        let fontSize = min(15, whiteWidth * 0.34)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: isC ? .heavy : .semibold),
            .foregroundColor: isC && keyColors[midi] == nil ? UIColor(red: 0.11, green: 0.69, blue: 0.96, alpha: 1) : color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        guard size.width < r.width + 4 else { return }
        (text as NSString).draw(at: CGPoint(x: r.midX - size.width / 2, y: r.maxY - size.height - 12), withAttributes: attrs)
    }

    private func drawFinger(_ finger: Int, center: CGPoint, dark: Bool) {
        let d: CGFloat = min(24, whiteWidth * 0.5)
        let circle = UIBezierPath(ovalIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
        UIColor(red: 1, green: 0.59, blue: 0, alpha: 1).setFill()
        circle.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: d * 0.62, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let text = "\(finger)" as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
    }

    // MARK: Cảm ứng

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let midi = note(at: touch.location(in: self)) else { continue }
            touchNotes[ObjectIdentifier(touch)] = midi
            onNoteOn?(midi)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let newNote = note(at: touch.location(in: self))
            let old = touchNotes[key]
            if newNote != old {
                if let old = old {
                    touchNotes[key] = nil
                    if !touchNotes.values.contains(old) { onNoteOff?(old) }
                }
                if let n = newNote {
                    touchNotes[key] = n
                    onNoteOn?(n)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if let midi = touchNotes[key] {
                touchNotes[key] = nil
                if !touchNotes.values.contains(midi) { onNoteOff?(midi) }
            }
        }
    }
}
