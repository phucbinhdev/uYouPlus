import Foundation

/// Nhận diện hợp âm từ các phím đang giữ.
public enum ChordDetector {
    struct Quality {
        let intervals: Set<Int>
        let suffix: String
        let vietnamese: String
    }

    static let qualities: [Quality] = [
        Quality(intervals: [0, 4, 7], suffix: "", vietnamese: "trưởng"),
        Quality(intervals: [0, 3, 7], suffix: "m", vietnamese: "thứ"),
        Quality(intervals: [0, 3, 6], suffix: "dim", vietnamese: "giảm"),
        Quality(intervals: [0, 4, 8], suffix: "aug", vietnamese: "tăng"),
        Quality(intervals: [0, 2, 7], suffix: "sus2", vietnamese: "sus2"),
        Quality(intervals: [0, 5, 7], suffix: "sus4", vietnamese: "sus4"),
        Quality(intervals: [0, 4, 7, 10], suffix: "7", vietnamese: "bảy (át)"),
        Quality(intervals: [0, 4, 7, 11], suffix: "maj7", vietnamese: "bảy trưởng"),
        Quality(intervals: [0, 3, 7, 10], suffix: "m7", vietnamese: "bảy thứ"),
        Quality(intervals: [0, 3, 6, 10], suffix: "m7♭5", vietnamese: "nửa giảm"),
        Quality(intervals: [0, 3, 6, 9], suffix: "dim7", vietnamese: "bảy giảm"),
        Quality(intervals: [0, 7], suffix: "5", vietnamese: "quãng năm")
    ]

    public struct Result: Equatable {
        public var root: Pitch
        public var symbol: String
        public var vietnameseName: String
        public var bass: Pitch
        /// Có phải thể đảo (nốt trầm khác nốt gốc).
        public var isInversion: Bool { bass.pitchClass != root.pitchClass }
    }

    public static func detect(_ midiNotes: [Int], naming: NoteNaming = .letter) -> Result? {
        let pcs = Set(midiNotes.map { (($0 % 12) + 12) % 12 })
        guard pcs.count >= 2, let lowest = midiNotes.min() else { return nil }
        let bassPC = ((lowest % 12) + 12) % 12
        // Ưu tiên gốc là nốt trầm nhất, rồi đến các nốt còn lại.
        let candidates = [bassPC] + pcs.subtracting([bassPC]).sorted()
        for quality in qualities where quality.intervals.count == pcs.count {
            for root in candidates {
                let intervals = Set(pcs.map { ($0 - root + 12) % 12 })
                if intervals == quality.intervals {
                    let rootPitch = Pitch(60 + root, prefersFlat: [3, 8, 10].contains(root))
                    let bass = Pitch(lowest)
                    var symbol = rootPitch.letterName() + quality.suffix
                    if bassPC != root { symbol += "/" + bass.letterName() }
                    let rootName = rootPitch.name(naming == .letter ? .letter : .solfege)
                    return Result(root: rootPitch, symbol: symbol,
                                  vietnameseName: "\(rootName) \(quality.vietnamese)", bass: bass)
                }
            }
        }
        return nil
    }

    /// Tên quãng giữa hai nốt (tiếng Việt).
    public static func intervalName(_ semitones: Int) -> String {
        let names = ["Đồng âm", "Quãng 2 thứ", "Quãng 2 trưởng", "Quãng 3 thứ", "Quãng 3 trưởng", "Quãng 4 đúng",
                     "Quãng 4 tăng", "Quãng 5 đúng", "Quãng 6 thứ", "Quãng 6 trưởng", "Quãng 7 thứ", "Quãng 7 trưởng",
                     "Quãng 8 đúng"]
        let s = abs(semitones)
        return s <= 12 ? names[s] : "Quãng \(s) cung nửa"
    }
}

// MARK: - MIDI

/// Thông điệp MIDI đã được giải mã (chỉ những loại ứng dụng cần).
public enum MIDIMessage: Equatable {
    case noteOn(note: Int, velocity: Int, channel: Int)
    case noteOff(note: Int, channel: Int)
    case controlChange(controller: Int, value: Int, channel: Int)
    case programChange(program: Int, channel: Int)
    case pitchBend(value: Int, channel: Int)
}

/// Bộ giải mã luồng byte MIDI 1.0 (hỗ trợ running status, bỏ qua SysEx và realtime).
public struct MIDIByteParser {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    private var inSysEx = false

    public init() {}

    public mutating func parse(_ bytes: [UInt8]) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        for b in bytes {
            if b >= 0xF8 { continue } // realtime: clock, active sensing...
            if b == 0xF0 { inSysEx = true; continue }
            if b == 0xF7 { inSysEx = false; continue }
            if inSysEx { continue }
            if b & 0x80 != 0 {
                if b >= 0xF0 { status = 0; data = []; continue } // system common: bỏ qua
                status = b
                data = []
                continue
            }
            guard status != 0 else { continue }
            data.append(b)
            let type = status & 0xF0
            let needed = (type == 0xC0 || type == 0xD0) ? 1 : 2
            if data.count == needed {
                if let msg = MIDIByteParser.decode(status: status, data1: data[0], data2: needed > 1 ? data[1] : 0) {
                    out.append(msg)
                }
                data = []
            }
        }
        return out
    }

    public static func decode(status: UInt8, data1: UInt8, data2: UInt8) -> MIDIMessage? {
        let channel = Int(status & 0x0F)
        let d1 = Int(data1 & 0x7F)
        let d2 = Int(data2 & 0x7F)
        switch status & 0xF0 {
        case 0x90: return d2 == 0 ? .noteOff(note: d1, channel: channel) : .noteOn(note: d1, velocity: d2, channel: channel)
        case 0x80: return .noteOff(note: d1, channel: channel)
        case 0xB0: return .controlChange(controller: d1, value: d2, channel: channel)
        case 0xC0: return .programChange(program: d1, channel: channel)
        case 0xE0: return .pitchBend(value: d1 | (d2 << 7), channel: channel)
        default: return nil
        }
    }

    /// Số từ 32-bit của một gói UMP theo loại thông điệp (4 bit cao của từ đầu tiên).
    public static func umpWordCount(_ firstWord: UInt32) -> Int {
        switch firstWord >> 28 {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    /// Giải mã một chuỗi từ UMP, bỏ qua các gói không phải MIDI 1.0 channel voice.
    public static func decodeUMPWords(_ words: [UInt32]) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if let msg = decodeUMP(w) { out.append(msg) }
            i += umpWordCount(w)
        }
        return out
    }

    /// Giải mã một từ Universal MIDI Packet loại 2 (MIDI 1.0 channel voice, 32-bit).
    public static func decodeUMP(_ word: UInt32) -> MIDIMessage? {
        guard (word >> 28) == 0x2 else { return nil }
        let status = UInt8((word >> 16) & 0xFF)
        let d1 = UInt8((word >> 8) & 0xFF)
        let d2 = UInt8(word & 0xFF)
        return decode(status: status, data1: d1, data2: d2)
    }
}
