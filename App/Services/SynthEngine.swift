import AVFoundation
import Foundation
import QuartzCore
import os

/// Bộ tổng hợp âm thanh piano đơn giản (cộng các hoạ âm, tắt dần theo hàm mũ).
/// Dùng cho bàn phím ảo, phát mẫu và tiếng gõ nhịp. Không cần file âm thanh.
final class SynthEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let core = SynthCore()
    private var started = false

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended { self?.restart() }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    func start() {
        guard !started else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Lỗi AVAudioSession: \(error)")
        }
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        core.sampleRate = sampleRate
        let core = self.core
        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, audioBufferList -> OSStatus in
            // Tự dựng mảng AudioBuffer thay cho UnsafeMutableAudioBufferListPointer
            // (kiểu này không có trên Mac Catalyst arm64).
            let buffersStart = UnsafeMutableRawPointer(audioBufferList)
                .advanced(by: MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!)
                .assumingMemoryBound(to: AudioBuffer.self)
            let buffers = UnsafeMutableBufferPointer(start: buffersStart, count: Int(audioBufferList.pointee.mNumberBuffers))
            guard let first = buffers.first, let data = first.mData else { return noErr }
            let samples = data.assumingMemoryBound(to: Float.self)
            let ts = timestamp.pointee
            let hostSeconds: Double
            if ts.mFlags.contains(.hostTimeValid) {
                hostSeconds = SynthCore.seconds(fromHostTime: ts.mHostTime)
            } else {
                hostSeconds = CACurrentMediaTime()
            }
            core.render(into: samples, frames: Int(frameCount), startTime: hostSeconds)
            // Sao chép sang các kênh còn lại (nếu có).
            for i in 1..<buffers.count {
                if let dst = buffers[i].mData {
                    dst.copyMemory(from: data, byteCount: Int(first.mDataByteSize))
                }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            started = true
        } catch {
            print("Không khởi động được âm thanh: \(error)")
        }
    }

    private func restart() {
        guard started else { return }
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        }
    }

    // MARK: Điều khiển

    func noteOn(_ midi: Int, velocity: Int = 90) {
        core.enqueue(.init(time: 0, kind: .noteOn(midi, Float(velocity) / 127)))
    }

    func noteOff(_ midi: Int) {
        core.enqueue(.init(time: 0, kind: .noteOff(midi)))
    }

    /// Phát một nốt trong `duration` giây.
    func play(_ midi: Int, duration: Double = 0.6, velocity: Int = 90, delay: Double = 0) {
        let now = CACurrentMediaTime() + delay
        core.enqueue(.init(time: now, kind: .noteOn(midi, Float(velocity) / 127)))
        core.enqueue(.init(time: now + duration, kind: .noteOff(midi)))
    }

    /// Phát một chuỗi nốt (giai điệu mẫu). `startTime` theo đồng hồ CACurrentMediaTime.
    func schedule(notes: [(midi: [Int], start: Double, duration: Double)], startTime: Double, velocity: Int = 85) {
        var events: [SynthCore.Event] = []
        for n in notes {
            for m in n.midi {
                events.append(.init(time: startTime + n.start, kind: .noteOn(m, Float(velocity) / 127)))
                events.append(.init(time: startTime + n.start + max(0.08, n.duration * 0.95), kind: .noteOff(m)))
            }
        }
        core.enqueue(events)
    }

    /// Tiếng gõ nhịp tại thời điểm `time` (CACurrentMediaTime).
    func click(at time: Double, accent: Bool) {
        core.enqueue(.init(time: time, kind: .click(accent)))
    }

    /// Huỷ các sự kiện hẹn giờ và tắt mọi nốt.
    func stopAll() {
        core.enqueue(.init(time: 0, kind: .allOff))
    }

    /// Âm thanh báo đúng / sai / hoàn thành.
    func playEffect(_ effect: SoundEffect) {
        let now = CACurrentMediaTime()
        switch effect {
        case .correct:
            core.enqueue([
                .init(time: now, kind: .noteOn(84, 0.45)), .init(time: now + 0.09, kind: .noteOff(84)),
                .init(time: now + 0.09, kind: .noteOn(88, 0.5)), .init(time: now + 0.35, kind: .noteOff(88))
            ])
        case .wrong:
            core.enqueue([
                .init(time: now, kind: .noteOn(52, 0.5)), .init(time: now, kind: .noteOn(58, 0.4)),
                .init(time: now + 0.25, kind: .noteOff(52)), .init(time: now + 0.25, kind: .noteOff(58))
            ])
        case .complete:
            let notes = [72, 76, 79, 84]
            var events: [SynthCore.Event] = []
            for (i, n) in notes.enumerated() {
                let t = now + Double(i) * 0.11
                events.append(.init(time: t, kind: .noteOn(n, 0.55)))
                events.append(.init(time: t + (i == notes.count - 1 ? 0.8 : 0.2), kind: .noteOff(n)))
            }
            core.enqueue(events)
        case .fail:
            let notes = [67, 63, 60]
            var events: [SynthCore.Event] = []
            for (i, n) in notes.enumerated() {
                let t = now + Double(i) * 0.18
                events.append(.init(time: t, kind: .noteOn(n, 0.5)))
                events.append(.init(time: t + 0.3, kind: .noteOff(n)))
            }
            core.enqueue(events)
        }
    }

    enum SoundEffect {
        case correct, wrong, complete, fail
    }
}

/// Phần xử lý âm thanh chạy trên luồng audio.
final class SynthCore {
    struct Event {
        enum Kind {
            case noteOn(Int, Float)
            case noteOff(Int)
            case click(Bool)
            case allOff
        }
        /// 0 = ngay lập tức; nếu không là thời điểm theo CACurrentMediaTime.
        var time: Double
        var kind: Kind
    }

    private struct Voice {
        var midi: Int
        var freq: Double
        var amp: Float
        var age: Double = 0
        var released = false
        var releaseAge: Double = 0
        /// Pha của tần số cơ bản (0..<2π). Hoạ âm thứ n có pha n × phase.
        var phase: Double = 0
        var isClick = false
        var decay: Double
    }

    var sampleRate: Double = 44_100
    /// Khóa được cấp phát cố định trên heap (an toàn hơn dùng `&` với thuộc tính).
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    private var pending: [Event] = []
    private var scheduled: [Event] = []
    private var voices: [Voice] = {
        var v: [Voice] = []
        v.reserveCapacity(64)
        return v
    }()
    private let maxVoices = 24
    private static let harmonics: [Float] = [1.0, 0.42, 0.22, 0.12, 0.07, 0.035]

    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static func seconds(fromHostTime t: UInt64) -> Double { Double(t) * timebase }

    func enqueue(_ e: Event) {
        os_unfair_lock_lock(lock)
        pending.append(e)
        os_unfair_lock_unlock(lock)
    }

    func enqueue(_ es: [Event]) {
        os_unfair_lock_lock(lock)
        pending.append(contentsOf: es)
        os_unfair_lock_unlock(lock)
    }

    private func apply(_ e: Event) {
        switch e.kind {
        case .noteOn(let midi, let vel):
            // Đánh lại cùng phím: nhả nốt cũ.
            for i in voices.indices where voices[i].midi == midi && !voices[i].released && !voices[i].isClick {
                voices[i].released = true
                voices[i].releaseAge = voices[i].age
            }
            let freq = 440 * pow(2, Double(midi - 69) / 12)
            // Nốt cao tắt nhanh hơn nốt trầm.
            let decay = 0.5 + max(0, Double(midi - 36)) * 0.045
            voices.append(Voice(midi: midi, freq: freq, amp: 0.35 * vel, decay: decay))
        case .noteOff(let midi):
            for i in voices.indices where voices[i].midi == midi && !voices[i].released && !voices[i].isClick {
                voices[i].released = true
                voices[i].releaseAge = voices[i].age
            }
        case .click(let accent):
            voices.append(Voice(midi: -1, freq: accent ? 2000 : 1400, amp: accent ? 0.5 : 0.35, isClick: true, decay: 60))
        case .allOff:
            scheduled.removeAll()
            for i in voices.indices where !voices[i].released {
                voices[i].released = true
                voices[i].releaseAge = voices[i].age
            }
        }
        if voices.count > maxVoices {
            voices.removeFirst(voices.count - maxVoices)
        }
    }

    func render(into out: UnsafeMutablePointer<Float>, frames: Int, startTime: Double) {
        os_unfair_lock_lock(lock)
        if !pending.isEmpty {
            for e in pending {
                if e.time == 0 {
                    apply(e)
                } else if case .allOff = e.kind {
                    apply(e)
                } else {
                    scheduled.append(e)
                }
            }
            pending.removeAll(keepingCapacity: true)
            scheduled.sort { $0.time < $1.time }
        }
        os_unfair_lock_unlock(lock)

        let dt = 1.0 / sampleRate
        let twoPi = 2.0 * Double.pi
        let harmonics = SynthCore.harmonics
        for frame in 0..<frames {
            let t = startTime + Double(frame) * dt
            while let first = scheduled.first, first.time <= t {
                scheduled.removeFirst()
                apply(first)
            }
            var sample: Float = 0
            var i = 0
            while i < voices.count {
                var v = voices[i]
                var env: Double
                if v.isClick {
                    env = exp(-v.age * v.decay)
                    sample += Float(sin(v.phase)) * v.amp * Float(env)
                } else {
                    let attack = min(1, v.age / 0.004)
                    env = attack * exp(-v.age * v.decay)
                    if v.released {
                        env *= exp(-(v.age - v.releaseAge) * 14)
                    }
                    var s = 0.0
                    for h in 0..<harmonics.count {
                        let n = Double(h + 1)
                        // Hoạ âm cao tắt nhanh hơn => tiếng "sáng" lúc đầu rồi dịu dần.
                        let hEnv = exp(-v.age * n * 0.9)
                        s += sin(v.phase * n) * Double(harmonics[h]) * hEnv
                    }
                    sample += Float(s * env) * v.amp
                }
                v.phase += twoPi * v.freq * dt
                if v.phase >= twoPi { v.phase -= twoPi }
                v.age += dt
                if env < 0.0004 && v.age > 0.01 {
                    voices.remove(at: i)
                    continue
                }
                voices[i] = v
                i += 1
            }
            out[frame] = tanhf(sample * 0.9)
        }
    }
}
