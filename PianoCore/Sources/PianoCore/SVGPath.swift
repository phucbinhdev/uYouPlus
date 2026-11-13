import Foundation

/// Lệnh vẽ đường (toạ độ tuyệt đối).
public enum PathCommand: Equatable {
    case move(Double, Double)
    case line(Double, Double)
    case quad(Double, Double, Double, Double)
    case cubic(Double, Double, Double, Double, Double, Double)
    case close
}

/// Bộ đọc đường SVG tối giản (M, L, H, V, Q, C, Z – chỉ toạ độ tuyệt đối).
public enum SVGPathParser {
    public static func parse(_ text: String) -> [PathCommand] {
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number); number = "" }
        }
        for ch in text {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush()
                tokens.append(String(ch))
            } else if ch == " " || ch == "," || ch == "\n" {
                flush()
            } else if ch == "-" && !number.isEmpty && number.last != "e" && number.last != "E" {
                flush()
                number = "-"
            } else {
                number.append(ch)
            }
        }
        flush()

        var commands: [PathCommand] = []
        var i = 0
        var current = "M"
        var x = 0.0, y = 0.0
        func next() -> Double? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return v
        }
        while i < tokens.count {
            if Double(tokens[i]) == nil {
                current = tokens[i]
                i += 1
                if current == "Z" || current == "z" { commands.append(.close); continue }
            }
            switch current {
            case "M":
                guard let a = next(), let b = next() else { return commands }
                commands.append(.move(a, b)); x = a; y = b
                current = "L" // các cặp số tiếp theo sau M là lệnh L
            case "L":
                guard let a = next(), let b = next() else { return commands }
                commands.append(.line(a, b)); x = a; y = b
            case "H":
                guard let a = next() else { return commands }
                commands.append(.line(a, y)); x = a
            case "V":
                guard let b = next() else { return commands }
                commands.append(.line(x, b)); y = b
            case "Q":
                guard let a = next(), let b = next(), let c = next(), let d = next() else { return commands }
                commands.append(.quad(a, b, c, d)); x = c; y = d
            case "C":
                guard let a = next(), let b = next(), let c = next(), let d = next(), let e = next(), let f = next() else {
                    return commands
                }
                commands.append(.cubic(a, b, c, d, e, f)); x = e; y = f
            default:
                return commands // lệnh không hỗ trợ
            }
        }
        return commands
    }

    /// Hộp bao (xấp xỉ bằng các điểm điều khiển).
    public static func bounds(_ commands: [PathCommand]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var xs: [Double] = []
        var ys: [Double] = []
        for c in commands {
            switch c {
            case .move(let a, let b), .line(let a, let b): xs.append(a); ys.append(b)
            case .quad(let a, let b, let c, let d): xs += [a, c]; ys += [b, d]
            case .cubic(let a, let b, let c, let d, let e, let f): xs += [a, c, e]; ys += [b, d, f]
            case .close: break
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return (minX, minY, maxX, maxY)
    }
}

/// Ký hiệu nhạc đã được đọc sẵn từ dữ liệu Bravura.
public struct MusicGlyph {
    public let advance: Double
    public let commands: [PathCommand]

    init(_ data: (advance: Double, path: String)) {
        advance = data.advance
        commands = SVGPathParser.parse(data.path)
    }

    public static let gClef = MusicGlyph(MusicGlyphData.gClef)
    public static let fClef = MusicGlyph(MusicGlyphData.fClef)
    public static let noteheadWhole = MusicGlyph(MusicGlyphData.noteheadWhole)
    public static let noteheadHalf = MusicGlyph(MusicGlyphData.noteheadHalf)
    public static let noteheadBlack = MusicGlyph(MusicGlyphData.noteheadBlack)
    public static let restWhole = MusicGlyph(MusicGlyphData.restWhole)
    public static let restHalf = MusicGlyph(MusicGlyphData.restHalf)
    public static let restQuarter = MusicGlyph(MusicGlyphData.restQuarter)
    public static let rest8th = MusicGlyph(MusicGlyphData.rest8th)
    public static let rest16th = MusicGlyph(MusicGlyphData.rest16th)
    public static let flag8thUp = MusicGlyph(MusicGlyphData.flag8thUp)
    public static let flag8thDown = MusicGlyph(MusicGlyphData.flag8thDown)
    public static let flag16thUp = MusicGlyph(MusicGlyphData.flag16thUp)
    public static let flag16thDown = MusicGlyph(MusicGlyphData.flag16thDown)
    public static let sharp = MusicGlyph(MusicGlyphData.accidentalSharp)
    public static let flat = MusicGlyph(MusicGlyphData.accidentalFlat)
    public static let natural = MusicGlyph(MusicGlyphData.accidentalNatural)
    public static let dot = MusicGlyph(MusicGlyphData.augmentationDot)

    /// Ký hiệu dấu lặng tương ứng với trường độ.
    public static func rest(forDuration d: Double) -> MusicGlyph {
        switch d {
        case 4...: return .restWhole
        case 2..<4: return .restHalf
        case 1..<2: return .restQuarter
        case 0.5..<1: return .rest8th
        default: return .rest16th
        }
    }

    /// Đầu nốt tương ứng với trường độ.
    public static func notehead(forDuration d: Double) -> MusicGlyph {
        switch d {
        case 4...: return .noteheadWhole
        case 2..<4: return .noteheadHalf
        default: return .noteheadBlack
        }
    }

    /// Có phải trường độ có chấm dôi.
    public static func isDotted(_ d: Double) -> Bool {
        [0.375, 0.75, 1.5, 3, 6].contains { abs($0 - d) < 0.001 }
    }

    /// Số đuôi móc (0, 1 hoặc 2) theo trường độ (bỏ chấm dôi).
    public static func flagCount(_ d: Double) -> Int {
        let base = isDotted(d) ? d / 1.5 : d
        if base >= 1 { return 0 }
        if base >= 0.5 { return 1 }
        return 2
    }
}
