import PianoCore
import SwiftUI

@main
struct PianoGoApp: App {
    @StateObject private var app: AppModel
    @StateObject private var input: NoteInput
    @StateObject private var midi: MIDIManager
    @StateObject private var synth: SynthEngine
    @StateObject private var bluetooth: BluetoothMIDIScanner

    init() {
        let app = AppModel()
        let input = NoteInput()
        let synth = SynthEngine()
        let midi = MIDIManager(input: input)
        let bluetooth = BluetoothMIDIScanner()

        input.synth = synth
        input.soundForMIDI = { [weak app] in app?.settings.soundForMIDI ?? false }
        bluetooth.onConnected = { [weak app, weak midi] id, name in
            app?.settings.lastPeripheralID = id.uuidString
            app?.settings.lastPeripheralName = name
            // CoreMIDI cần một chút thời gian để tạo thiết bị MIDI cho đàn.
            for delay in [0.5, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { midi?.refresh() }
            }
        }

        _app = StateObject(wrappedValue: app)
        _input = StateObject(wrappedValue: input)
        _synth = StateObject(wrappedValue: synth)
        _midi = StateObject(wrappedValue: midi)
        _bluetooth = StateObject(wrappedValue: bluetooth)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(input)
                .environmentObject(midi)
                .environmentObject(synth)
                .environmentObject(bluetooth)
                .preferredColorScheme(.light)
                .onAppear(perform: startServices)
        }
    }

    private func startServices() {
        synth.start()
        synth.volume = Float(app.settings.volume)
        midi.start()
        if app.settings.autoReconnect {
            bluetooth.reconnect(to: app.settings.lastPeripheralID)
        }
    }
}
