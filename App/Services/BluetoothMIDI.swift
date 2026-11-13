import CoreAudioKit
import CoreBluetooth
import SwiftUI

/// Bảng kết nối Bluetooth MIDI có sẵn của Apple (CABTMIDICentralViewController).
struct BluetoothMIDIPicker: UIViewControllerRepresentable {
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = CABTMIDICentralViewController()
        picker.title = "Đàn Bluetooth MIDI"
        picker.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done))
        return UINavigationController(rootViewController: picker)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        @objc func done() { onDone() }
    }
}

/// Tìm và kết nối đàn hỗ trợ chuẩn Bluetooth LE MIDI bằng CoreBluetooth.
/// Khi đã kết nối, iOS tự đưa đàn vào CoreMIDI và `MIDIManager` sẽ nhận được nốt.
final class BluetoothMIDIScanner: NSObject, ObservableObject {
    /// UUID dịch vụ chuẩn của Bluetooth LE MIDI.
    static let midiService = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")

    struct Peripheral: Identifiable, Hashable {
        let id: UUID
        var name: String
        var rssi: Int
    }

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var found: [Peripheral] = []
    @Published private(set) var connectingID: UUID?
    @Published private(set) var connectedIDs: Set<UUID> = []
    @Published private(set) var isScanning = false

    /// Gọi khi kết nối thành công (id, tên) — dùng để ghi nhớ đàn cho lần sau.
    var onConnected: ((UUID, String) -> Void)?

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var pendingReconnect: UUID?
    private var wantsScan = false

    var isPoweredOn: Bool { state == .poweredOn }

    /// Khởi tạo CoreBluetooth (iOS sẽ hỏi quyền Bluetooth lần đầu).
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        activate()
        wantsScan = true
        guard let central = central, central.state == .poweredOn else { return }
        // Đàn đã được kết nối sẵn bởi hệ thống / ứng dụng khác.
        for p in central.retrieveConnectedPeripherals(withServices: [BluetoothMIDIScanner.midiService]) {
            remember(p, rssi: 0)
        }
        central.scanForPeripherals(withServices: [BluetoothMIDIScanner.midiService],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
        isScanning = false
    }

    func connect(_ id: UUID) {
        guard let central = central, let p = peripherals[id] else { return }
        connectingID = id
        central.connect(p, options: nil)
    }

    func disconnect(_ id: UUID) {
        guard let central = central, let p = peripherals[id] else { return }
        central.cancelPeripheralConnection(p)
    }

    /// Tự động kết nối lại đàn đã dùng lần trước (khi đàn bật Bluetooth).
    func reconnect(to idString: String?) {
        guard let idString = idString, let id = UUID(uuidString: idString) else { return }
        activate()
        pendingReconnect = id
        tryPendingReconnect()
    }

    private func tryPendingReconnect() {
        guard let central = central, central.state == .poweredOn, let id = pendingReconnect else { return }
        pendingReconnect = nil
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            remember(p, rssi: 0)
            connectingID = id
            // Lệnh connect của CoreBluetooth không hết hạn: khi đàn bật lên sẽ tự kết nối.
            central.connect(p, options: nil)
        }
    }

    private func remember(_ p: CBPeripheral, rssi: Int) {
        peripherals[p.identifier] = p
        let name = p.name ?? "Đàn Bluetooth MIDI"
        if let idx = found.firstIndex(where: { $0.id == p.identifier }) {
            found[idx].name = name
            if rssi != 0 { found[idx].rssi = rssi }
        } else {
            found.append(Peripheral(id: p.identifier, name: name, rssi: rssi))
        }
    }
}

extension BluetoothMIDIScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn {
            tryPendingReconnect()
            if wantsScan { startScan() }
        } else {
            isScanning = false
            connectedIDs.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        remember(peripheral, rssi: RSSI.intValue)
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           let idx = found.firstIndex(where: { $0.id == peripheral.identifier }) {
            found[idx].name = localName
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedIDs.insert(peripheral.identifier)
        if connectingID == peripheral.identifier { connectingID = nil }
        let name = found.first(where: { $0.id == peripheral.identifier })?.name ?? peripheral.name ?? "Đàn Bluetooth MIDI"
        onConnected?(peripheral.identifier, name)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if connectingID == peripheral.identifier { connectingID = nil }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedIDs.remove(peripheral.identifier)
        if connectingID == peripheral.identifier { connectingID = nil }
    }
}
