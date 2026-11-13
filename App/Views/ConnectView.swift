import CoreBluetooth
import PianoCore
import SwiftUI

/// Kết nối đàn: hướng dẫn cho Bora BX20, tìm đàn Bluetooth MIDI, kiểm tra nốt.
struct ConnectView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var midi: MIDIManager
    @EnvironmentObject private var bluetooth: BluetoothMIDIScanner
    @EnvironmentObject private var input: NoteInput
    @Environment(\.presentationMode) private var presentationMode
    @State private var showApplePicker = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusCard
                    guideCard
                    scanCard
                    testCard
                    optionsCard
                }
                .padding(22)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color.duoPanel.ignoresSafeArea())
            .navigationTitle("Kết nối đàn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { presentationMode.wrappedValue.dismiss() }
                        .font(.rounded(17, .heavy))
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showApplePicker, onDismiss: { midi.refresh() }) {
            BluetoothMIDIPicker { showApplePicker = false }
        }
        .onAppear {
            midi.refresh()
            bluetooth.startScan()
        }
        .onDisappear { bluetooth.stopScan() }
    }

    // MARK: Trạng thái

    private var statusCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(midi.isConnected ? Color.duoGreenLight : Color.duoBlueLight)
                Image(systemName: midi.isConnected ? "checkmark.circle.fill" : "pianokeys")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(midi.isConnected ? .duoGreen : .duoBlue)
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 6) {
                Text(midi.isConnected ? "Đã kết nối" : "Chưa kết nối đàn")
                    .font(.rounded(24, .heavy))
                    .foregroundColor(.duoText)
                if midi.isConnected {
                    ForEach(midi.devices) { d in
                        Label(d.name, systemImage: d.isBluetooth ? "dot.radiowaves.left.and.right" : "cable.connector")
                            .font(.rounded(16, .bold))
                            .foregroundColor(.duoSubtext)
                    }
                } else {
                    Text("Bạn vẫn có thể học bằng bàn phím trên màn hình.")
                        .font(.rounded(16, .semibold))
                        .foregroundColor(.duoSubtext)
                }
            }
            Spacer()
        }
        .card(padding: 18)
    }

    // MARK: Hướng dẫn

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cách kết nối đàn Bora BX20")
                .font(.rounded(20, .heavy))
                .foregroundColor(.duoText)
            step(1, "Bật đàn và bật Bluetooth trên đàn (nút/biểu tượng Bluetooth – đèn sẽ nhấp nháy).")
            step(2, "KHÔNG ghép đôi trong Cài đặt › Bluetooth của iPad. Bluetooth MIDI được kết nối ngay trong ứng dụng này.")
            step(3, "Đợi tên đàn xuất hiện ở mục “Tìm đàn” bên dưới (thường là BX20, BORA, Piano hoặc BLE-MIDI) rồi bấm “Kết nối”.")
            step(4, "Nhấn thử vài phím trên đàn: ô “Kiểm tra” sẽ hiện tên nốt bạn vừa đánh.")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundColor(.duoBlue)
                Text("Nếu đàn đang kết nối với điện thoại hoặc ứng dụng khác, hãy ngắt kết nối ở đó trước. Bạn cũng có thể nối đàn với iPad bằng cáp USB (cổng USB‑MIDI của đàn) – ứng dụng sẽ tự nhận.")
                    .font(.rounded(15, .semibold))
                    .foregroundColor(.duoSubtext)
            }
        }
        .card(padding: 18)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.rounded(16, .heavy))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.duoGreen))
            Text(text)
                .font(.rounded(17, .semibold))
                .foregroundColor(.duoText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Tìm đàn

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tìm đàn (Bluetooth MIDI)")
                    .font(.rounded(20, .heavy))
                    .foregroundColor(.duoText)
                Spacer()
                if bluetooth.isScanning {
                    ProgressView()
                }
            }
            switch bluetooth.state {
            case .poweredOff:
                warning("Bluetooth của iPad đang tắt. Hãy bật trong Trung tâm điều khiển hoặc Cài đặt.")
            case .unauthorized:
                warning("Ứng dụng chưa được phép dùng Bluetooth. Vào Cài đặt › Piano Go › bật Bluetooth.")
            case .unsupported:
                warning("Thiết bị này không hỗ trợ Bluetooth LE.")
            default:
                EmptyView()
            }
            if bluetooth.found.isEmpty {
                Text(bluetooth.isScanning ? "Đang tìm đàn… hãy chắc chắn Bluetooth trên đàn đã bật." : "Chưa tìm thấy đàn nào.")
                    .font(.rounded(16, .semibold))
                    .foregroundColor(.duoSubtext)
            }
            ForEach(bluetooth.found) { p in
                HStack(spacing: 14) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.duoBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.rounded(18, .heavy)).foregroundColor(.duoText)
                        Text(statusText(p)).font(.rounded(14, .semibold)).foregroundColor(.duoSubtext)
                    }
                    Spacer()
                    if bluetooth.connectedIDs.contains(p.id) {
                        Button("Ngắt") { bluetooth.disconnect(p.id) }
                            .buttonStyle(DuoButtonStyle(color: .duoRed, height: 40, fullWidth: false))
                    } else if bluetooth.connectingID == p.id {
                        ProgressView()
                    } else {
                        Button("Kết nối") { bluetooth.connect(p.id) }
                            .buttonStyle(DuoButtonStyle(color: .duoGreen, height: 40, fullWidth: false))
                    }
                }
                .padding(.vertical, 4)
            }
            HStack(spacing: 12) {
                Button {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                } label: {
                    Label(bluetooth.isScanning ? "Dừng tìm" : "Tìm lại", systemImage: "magnifyingglass")
                }
                .buttonStyle(DuoButtonStyle(color: .duoBlue, height: 44, fullWidth: false))
                Button {
                    showApplePicker = true
                } label: {
                    Label("Bảng kết nối của Apple", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(DuoButtonStyle(color: .duoPurple, height: 44, fullWidth: false))
            }
            Text("Không thấy đàn hoặc kết nối xong mà chưa nhận nốt? Dùng “Bảng kết nối của Apple” – đây là cách kết nối Bluetooth MIDI chuẩn của iOS.")
                .font(.rounded(14, .semibold))
                .foregroundColor(.duoGrayDark)
        }
        .card(padding: 18)
    }

    private func statusText(_ p: BluetoothMIDIScanner.Peripheral) -> String {
        if bluetooth.connectedIDs.contains(p.id) {
            return midi.isConnected ? "Đã kết nối – đang nhận nốt" : "Đã kết nối Bluetooth, đang chờ MIDI…"
        }
        if p.id.uuidString == app.settings.lastPeripheralID { return "Đã dùng lần trước" }
        return p.rssi != 0 ? "Tín hiệu \(p.rssi) dBm" : "Sẵn sàng"
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.duoOrange)
            Text(text).font(.rounded(15, .bold)).foregroundColor(.duoText)
        }
    }

    // MARK: Kiểm tra

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kiểm tra")
                .font(.rounded(20, .heavy))
                .foregroundColor(.duoText)
            HStack(spacing: 18) {
                VStack {
                    if let e = input.lastEvent {
                        Text(e.pitch.name(app.settings.naming))
                            .font(.rounded(40, .heavy))
                            .foregroundColor(e.source == .midi ? .duoGreen : .duoBlue)
                        Text(e.source == .midi ? "từ đàn • lực \(e.velocity)" : "từ màn hình")
                            .font(.rounded(14, .bold))
                            .foregroundColor(.duoSubtext)
                    } else {
                        Text("—")
                            .font(.rounded(40, .heavy))
                            .foregroundColor(.duoGray)
                        Text("Hãy nhấn một phím")
                            .font(.rounded(14, .bold))
                            .foregroundColor(.duoSubtext)
                    }
                }
                .frame(width: 170, height: 110)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.duoPanel))
                PianoKeyboardView(range: 48...84, pressed: input.held, naming: app.settings.naming, labelAllKeys: false,
                                  onNoteOn: { input.touchDown($0) }, onNoteOff: { input.touchUp($0) })
                    .frame(height: 110)
            }
            if input.sustain {
                Label("Đang giữ pedal", systemImage: "shoeprints.fill")
                    .font(.rounded(14, .bold))
                    .foregroundColor(.duoPurple)
            }
        }
        .card(padding: 18)
    }

    // MARK: Tùy chọn

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Tự động kết nối lại đàn đã dùng", isOn: $app.settings.autoReconnect)
            Toggle("Phát tiếng trên iPad khi đánh đàn thật", isOn: $app.settings.soundForMIDI)
            Text("Đàn BX20 tự phát tiếng nên thường không cần bật mục này.")
                .font(.rounded(14, .semibold))
                .foregroundColor(.duoGrayDark)
        }
        .font(.rounded(17, .bold))
        .foregroundColor(.duoText)
        .toggleStyle(SwitchToggleStyle(tint: .duoGreen))
        .card(padding: 18)
    }
}
