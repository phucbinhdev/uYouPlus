import CoreMIDI
import Foundation
import PianoCore
import QuartzCore

/// Nhận nốt nhạc từ mọi nguồn MIDI (Bluetooth MIDI, USB, mạng) qua CoreMIDI.
final class MIDIManager: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: MIDIUniqueID
        let name: String
        let isBluetooth: Bool
    }

    /// Các thiết bị MIDI đang gửi được nốt tới ứng dụng.
    @Published private(set) var devices: [Device] = []
    @Published private(set) var lastActivity: Date?
    @Published private(set) var errorMessage: String?

    var isConnected: Bool { !devices.isEmpty }
    var connectedName: String? { devices.first?.name }

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connectedRefs: Set<MIDIEndpointRef> = []
    private let input: NoteInput

    init(input: NoteInput) {
        self.input = input
    }

    func start() {
        guard client == 0 else { return }
        var status = MIDIClientCreateWithBlock("PianoGo" as CFString, &client) { [weak self] _ in
            // Có thiết bị được thêm / bớt.
            DispatchQueue.main.async { self?.refresh() }
        }
        guard status == noErr else {
            errorMessage = "Không khởi tạo được CoreMIDI (mã \(status))."
            return
        }
        status = MIDIInputPortCreateWithProtocol(client, "PianoGo Input" as CFString, ._1_0, &port) { [weak self] eventList, _ in
            self?.receive(eventList)
        }
        guard status == noErr else {
            errorMessage = "Không tạo được cổng MIDI (mã \(status))."
            return
        }
        refresh()
    }

    /// Quét lại danh sách nguồn MIDI và kết nối với nguồn mới.
    func refresh() {
        guard port != 0 else { return }
        var current: Set<MIDIEndpointRef> = []
        var list: [Device] = []
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            let name = MIDIManager.string(src, kMIDIPropertyDisplayName) ?? MIDIManager.string(src, kMIDIPropertyName) ?? "Thiết bị MIDI"
            // Bỏ qua phiên MIDI qua mạng mặc định của hệ thống.
            if name.localizedCaseInsensitiveContains("Network Session") { continue }
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(src, kMIDIPropertyOffline, &offline)
            if offline != 0 { continue }
            current.insert(src)
            if !connectedRefs.contains(src) {
                MIDIPortConnectSource(port, src, nil)
            }
            var uid: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &uid)
            list.append(Device(id: uid, name: name, isBluetooth: MIDIManager.isBluetooth(src)))
        }
        for gone in connectedRefs.subtracting(current) {
            MIDIPortDisconnectSource(port, gone)
        }
        let hadDevices = !devices.isEmpty
        connectedRefs = current
        devices = list
        if hadDevices && list.isEmpty {
            input.releaseAll(source: .midi)
        }
    }

    // MARK: Nhận dữ liệu (luồng MIDI)

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        var words: [UInt32] = []
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            var raw = packet.pointee.words
            withUnsafeBytes(of: &raw) { bytes in
                let buffer = bytes.bindMemory(to: UInt32.self)
                words.append(contentsOf: buffer.prefix(count))
            }
        }
        let messages = MIDIByteParser.decodeUMPWords(words)
        guard !messages.isEmpty else { return }
        let time = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self] in
            self?.dispatch(messages, time: time)
        }
    }

    private func dispatch(_ messages: [MIDIMessage], time: Double) {
        for message in messages {
            switch message {
            case .noteOn(let note, let velocity, _):
                input.send(NoteEvent(pitch: Pitch(note), isOn: true, velocity: velocity, time: time, source: .midi))
            case .noteOff(let note, _):
                input.send(NoteEvent(pitch: Pitch(note), isOn: false, velocity: 0, time: time, source: .midi))
            case .controlChange(let controller, let value, _):
                if controller == 64 { input.setSustain(value >= 64) }
                if controller == 123 || controller == 120 { input.releaseAll(source: .midi) }
            default:
                break
            }
        }
        lastActivity = Date()
    }

    // MARK: Tiện ích CoreMIDI

    private static func string(_ obj: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(obj, property, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func isBluetooth(_ endpoint: MIDIEndpointRef) -> Bool {
        var entity = MIDIEntityRef()
        var device = MIDIDeviceRef()
        guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, MIDIEntityGetDevice(entity, &device) == noErr else {
            return false
        }
        let owner = string(device, kMIDIPropertyDriverOwner) ?? ""
        return owner.localizedCaseInsensitiveContains("Bluetooth")
    }
}
