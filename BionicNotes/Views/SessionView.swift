import SwiftUI

struct SessionView: View {
    @Bindable var session: NoteSession
    @State private var recorder = AudioRecorder()
    @State private var player = AudioPlayer()

    var body: some View {
        VStack(spacing: 32) {
            TextField("Titel", text: $session.title)
                .font(.title2.bold())
                .textFieldStyle(.roundedBorder)

            if session.hasAudio && recorder.state == .idle {
                PlayerControls(player: player)
            } else {
                RecorderControls(recorder: recorder, onStart: startRecording, onStop: finishRecording)
            }

            if let message = recorder.errorMessage ?? player.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        // Während der Aufnahme nicht versehentlich rausnavigieren
        .navigationBarBackButtonHidden(recorder.state != .idle)
        .onAppear {
            if session.hasAudio { player.load(url: session.audioURL) }
        }
        .onDisappear { player.stop() }
    }

    private func startRecording() {
        Task { await recorder.start(writingTo: session.audioURL) }
    }

    private func finishRecording() {
        session.duration = recorder.stop()
        session.hasAudio = true
        player.load(url: session.audioURL)
    }
}

private struct RecorderControls: View {
    let recorder: AudioRecorder
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(recorder.elapsed.clockString)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()

            LevelMeter(level: recorder.level)
                .frame(height: 10)

            HStack(spacing: 40) {
                switch recorder.state {
                case .idle:
                    RoundButton(systemImage: "record.circle.fill", tint: .red, label: "Aufnahme starten", action: onStart)
                case .recording:
                    RoundButton(systemImage: "pause.fill", tint: .orange, label: "Pause", action: recorder.pause)
                    RoundButton(systemImage: "stop.fill", tint: .gray, label: "Beenden", action: onStop)
                case .paused:
                    RoundButton(systemImage: "record.circle.fill", tint: .red, label: "Fortsetzen", action: recorder.resume)
                    RoundButton(systemImage: "stop.fill", tint: .gray, label: "Beenden", action: onStop)
                }
            }
        }
    }
}

private struct PlayerControls: View {
    let player: AudioPlayer

    var body: some View {
        VStack(spacing: 16) {
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.1))
            HStack {
                Text(player.currentTime.clockString)
                Spacer()
                Text(player.duration.clockString)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            HStack(spacing: 40) {
                RoundButton(systemImage: "gobackward.15", tint: .secondary, label: "15 s zurück") { player.skip(by: -15) }
                RoundButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", tint: .accentColor,
                            label: player.isPlaying ? "Pause" : "Abspielen", action: player.toggle)
                RoundButton(systemImage: "goforward.15", tint: .secondary, label: "15 s vor") { player.skip(by: 15) }
            }
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(level > 0.85 ? Color.red : Color.green)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
    }
}

private struct RoundButton: View {
    let systemImage: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .frame(width: 72, height: 72)
                .background(Circle().fill(tint.opacity(0.15)))
                .foregroundStyle(tint)
        }
        .accessibilityLabel(label)
    }
}
