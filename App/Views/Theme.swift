import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }

    /// Màu tối hơn (dùng cho viền "nổi" phía dưới nút).
    func darker(_ amount: CGFloat = 0.18) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: min(1, s + 0.05), brightness: max(0, b - amount), alpha: a))
    }

    static let duoGreen = Color(hex: "58CC02")
    static let duoGreenLight = Color(hex: "D7FFB8")
    static let duoBlue = Color(hex: "1CB0F6")
    static let duoBlueLight = Color(hex: "DDF4FF")
    static let duoRed = Color(hex: "FF4B4B")
    static let duoRedLight = Color(hex: "FFDFE0")
    static let duoOrange = Color(hex: "FF9600")
    static let duoYellow = Color(hex: "FFC800")
    static let duoPurple = Color(hex: "CE82FF")
    static let duoGray = Color(hex: "E5E5E5")
    static let duoGrayDark = Color(hex: "AFAFAF")
    static let duoText = Color(hex: "4B4B4B")
    static let duoSubtext = Color(hex: "777777")
    static let duoBackground = Color(hex: "FFFFFF")
    static let duoPanel = Color(hex: "F7F7F7")
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Nút "nổi" đặc trưng: có viền dưới đậm, nhấn xuống thì lún.
struct DuoButtonStyle: ButtonStyle {
    var color: Color = .duoGreen
    var textColor: Color = .white
    var height: CGFloat = 52
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = isEnabled ? color : Color.duoGray
        let depth: CGFloat = 4
        let pressed = configuration.isPressed
        return configuration.label
            .font(.rounded(17, .heavy))
            .textCase(.uppercase)
            .foregroundColor(isEnabled ? textColor : .duoGrayDark)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(fill.darker())
                        .offset(y: depth)
                    RoundedRectangle(cornerRadius: 16).fill(fill)
                        .offset(y: pressed ? depth : 0)
                }
            )
            .offset(y: pressed ? depth / 2 : 0)
            .padding(.bottom, depth)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// Nút viền trắng (lựa chọn trắc nghiệm).
struct DuoChoiceStyle: ButtonStyle {
    var selected = false
    var state: ChoiceState = .normal

    enum ChoiceState { case normal, correct, wrong }

    func makeBody(configuration: Configuration) -> some View {
        let (border, fill, text): (Color, Color, Color) = {
            switch state {
            case .correct: return (.duoGreen, .duoGreenLight, Color(hex: "58A700"))
            case .wrong: return (.duoRed, .duoRedLight, Color(hex: "EA2B2B"))
            case .normal:
                return selected ? (.duoBlue, .duoBlueLight, Color(hex: "1899D6")) : (.duoGray, .white, .duoText)
            }
        }()
        let pressed = configuration.isPressed
        return configuration.label
            .font(.rounded(20, .bold))
            .foregroundColor(text)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(border)
                        .offset(y: pressed ? 0 : 3)
                    RoundedRectangle(cornerRadius: 16).fill(fill)
                    RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 2)
                }
            )
            .offset(y: pressed ? 2 : 0)
            .padding(.bottom, 3)
    }
}

/// Thanh tiến độ bo tròn.
struct DuoProgressBar: View {
    var value: Double
    var color: Color = .duoGreen
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.duoGray)
                Capsule().fill(color)
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * CGFloat(min(1, max(0, value)))))
                    .overlay(
                        Capsule().fill(Color.white.opacity(0.3))
                            .frame(height: height * 0.28)
                            .padding(.horizontal, height * 0.5)
                            .offset(y: -height * 0.18),
                        alignment: .top
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
            }
        }
        .frame(height: height)
    }
}

/// Linh vật "Nốt Nhạc" vẽ bằng hình khối.
struct MascotView: View {
    enum Mood { case happy, sad, thinking, excited }
    var mood: Mood = .happy
    var size: CGFloat = 96
    @State private var bounce = false

    var body: some View {
        let s = size
        ZStack {
            // Thân nốt nhạc
            Ellipse()
                .fill(Color.duoGreen)
                .frame(width: s * 0.78, height: s * 0.62)
                .rotationEffect(.degrees(-18))
                .offset(x: -s * 0.08, y: s * 0.16)
            // Cán và đuôi nốt
            RoundedRectangle(cornerRadius: s * 0.04)
                .fill(Color.duoGreen.darker(0.1))
                .frame(width: s * 0.09, height: s * 0.72)
                .offset(x: s * 0.27, y: -s * 0.15)
            Capsule()
                .fill(Color.duoGreen.darker(0.1))
                .frame(width: s * 0.3, height: s * 0.1)
                .rotationEffect(.degrees(35))
                .offset(x: s * 0.38, y: -s * 0.38)
            // Mắt
            HStack(spacing: s * 0.08) {
                eye
                eye
            }
            .offset(x: -s * 0.08, y: s * 0.08)
            // Miệng
            mouth
                .offset(x: -s * 0.08, y: s * 0.3)
        }
        .frame(width: s, height: s)
        .offset(y: bounce ? -s * 0.04 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bounce = true }
        }
    }

    private var eye: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: size * 0.2, height: size * 0.2)
            Circle().fill(Color.duoText)
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: mood == .thinking ? size * 0.04 : 0, y: mood == .sad ? size * 0.03 : -size * 0.01)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy, .excited:
            HalfCircle()
                .fill(mood == .excited ? Color.duoRed : Color.duoText)
                .frame(width: size * (mood == .excited ? 0.2 : 0.16), height: size * (mood == .excited ? 0.1 : 0.07))
        case .sad:
            HalfCircle()
                .fill(Color.duoText)
                .frame(width: size * 0.16, height: size * 0.06)
                .rotationEffect(.degrees(180))
        case .thinking:
            Capsule().fill(Color.duoText).frame(width: size * 0.12, height: size * 0.03)
        }
    }
}

/// Nửa hình tròn phía dưới (cái miệng cười).
struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        p.closeSubpath()
        return p
    }
}

/// Bong bóng lời thoại.
struct SpeechBubble<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.duoGray, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            )
    }
}

/// Khung thẻ có viền xám.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.duoGray, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Hiệu ứng rung lắc khi sai.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0))
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded())
    if s >= 3600 { return "\(s / 3600) giờ \((s % 3600) / 60) phút" }
    return String(format: "%d:%02d", s / 60, s % 60)
}
