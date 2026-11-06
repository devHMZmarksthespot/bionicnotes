import SwiftUI

struct SessionView: View {
    @Bindable var session: NoteSession
    @State private var recorder = AudioRecorder()
    @State private var player = AudioPlayer()
    @State private var transcript = TranscriptStore()
    @State private var transcriber: LiveTranscriber?
    @State private var isStarting = false

    private var isPlaybackMode: Bool { session.hasAudio && recorder.state == .idle && !isStarting }

    var body: some View {
        VStack(spacing: 20) {
            TextField("Titel", text: $session.title)
                .font(.title2.bold())
                .textFieldStyle(.roundedBorder)

            if isPlaybackMode {
                PlayerControls(player: player)
            } else {
                RecorderControls(recorder: recorder, startDisabled: isStarting,
                                 onStart: startRecording, onStop: finishRecording)
                if recorder.state == .idle {
                    Picker("Sprache", selection: $session.language) {
                        ForEach(TranscriptionLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isStarting)
                }
            }

            TranscriptStatusView(status: transcript.status)

            if let message = recorder.errorMessage ?? player.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            }

            if transcript.isEmpty {
                Spacer()
            } else {
                TranscriptView(store: transcript,
                               playbackTime: isPlaybackMode ? player.currentTime : nil,
                               onSelect: isPlaybackMode ? jump(to:) : nil)
            }
        }
        .padding()
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        // Während der Aufnahme nicht versehentlich rausnavigieren
        .navigationBarBackButtonHidden(recorder.state != .idle || isStarting)
        .onAppear {
            if session.hasAudio {
                player.load(url: session.audioURL)
                transcript.load(from: session.transcriptURL)
            }
        }
        .onDisappear { player.stop() }
    }

    private func startRecording() {
        guard !isStarting else { return }
        isStarting = true
        player.stop()
        TranscriptionLanguage.remember(session.language)
        Task {
            defer { isStarting = false }
            transcript.reset()
            transcript.status = .preparing
            let store = transcript

            // 1. Transkription vorbereiten (lädt einmalig das Sprachmodell).
            //    Klappt das nicht, wird trotzdem aufgenommen – nur ohne Live-Transkript.
            var live: LiveTranscriber?
            do {
                let t = try await LiveTranscriber.prepare(locale: Locale(identifier: session.language)) { progress in
                    Task { @MainActor in
                        switch store.status {
                        case .preparing, .downloading: store.status = .downloading(progress)
                        default: break
                        }
                    }
                }
                try await t.start { update in store.apply(update) }
                live = t
                transcript.status = .listening
            } catch {
                transcript.status = .unavailable(error.localizedDescription)
            }

            // 2. Aufnahme starten; jeder Mikrofon-Puffer geht zusätzlich an die Transkription.
            transcriber = live
            let started = await recorder.start(writingTo: session.audioURL,
                                               onBuffer: live.map { t in { @Sendable buffer, _ in t.feed(buffer) } })
            if !started, let live {
                await live.finish()
                transcriber = nil
                transcript.status = .idle
            }
        }
    }

    private func finishRecording() {
        session.duration = recorder.stop()
        session.hasAudio = true
        player.load(url: session.audioURL)

        let live = transcriber
        transcriber = nil
        let store = transcript
        let url = session.transcriptURL
        let language = session.language
        Task {
            if let live { await live.finish() }
            if case .listening = store.status { store.status = .idle }
            store.save(to: url, locale: language)
        }
    }

    private func jump(to segment: TranscriptSegment) {
        player.seek(to: segment.start)
        if !player.isPlaying { player.toggle() }
    }
}

private struct RecorderControls: View {
    let recorder: AudioRecorder
    let startDisabled: Bool
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
                        .disabled(startDisabled)
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
