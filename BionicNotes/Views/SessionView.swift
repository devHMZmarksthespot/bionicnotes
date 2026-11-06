import SwiftUI

struct SessionView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var session: NoteSession
    @State private var recorder = AudioRecorder()
    @State private var player = AudioPlayer()
    @State private var transcript = TranscriptStore()
    @State private var transcriber: LiveTranscriber?
    @State private var isStarting = false
    @State private var markers = MarkerStore()
    @State private var notes = NotesStore()
    @State private var photos = PhotoStore()
    @State private var isCameraShown = false
    @State private var isScannerShown = false
    @State private var captureTime: TimeInterval?
    @State private var selectedPhoto: SessionPhoto?
    @State private var pane: CompactPane = .notes

    private var isPlaybackMode: Bool { session.hasAudio && recorder.state == .idle && !isStarting }
    private var isCompact: Bool { sizeClass == .compact }
    private var isRecordingActive: Bool { recorder.state != .idle }

    var body: some View {
        VStack(spacing: 10) {
            if isCompact && isRecordingActive && pane == .quick {
                panePicker
                QuickModeView(recorder: recorder,
                              transcript: transcript,
                              isListening: transcript.status == .listening,
                              onMarker: addPhoneMarker,
                              onPhoto: { openCapture(scanner: false) },
                              onSlide: { openCapture(scanner: true) },
                              onStop: finishRecording)
                if recorder.isInputSilent {
                    SilentMicBanner()
                }
                Spacer(minLength: 0)
            } else {
                mainContent
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        // Titel direkt in der Navigationsleiste umbenennen (Tippen auf den Titel)
        .navigationTitle($session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            if recorder.state == .idle && !isPlaybackMode {
                ToolbarItem(placement: .topBarTrailing) { languageMenu }
            }
            ToolbarItem(placement: .topBarTrailing) { cameraMenu }
        }
        .fullScreenCover(isPresented: $isCameraShown) {
            CameraPicker(onImage: { image in
                photos.add(image, kind: .photo, time: captureTime)
                isCameraShown = false
            }, onCancel: { isCameraShown = false })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isScannerShown) {
            SlideScanner(onScan: { pages in
                addSlides(pages)
                isScannerShown = false
            }, onCancel: { isScannerShown = false })
            .ignoresSafeArea()
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, store: photos, onJump: isPlaybackMode ? jump(toTime:) : nil)
        }
        // Während der Aufnahme nicht versehentlich rausnavigieren
        .navigationBarBackButtonHidden(recorder.state != .idle || isStarting)
        .onAppear {
            if session.hasAudio {
                player.load(url: session.audioURL)
                transcript.load(from: session.transcriptURL)
            }
            markers.load(from: session.markersURL)
            notes.load(drawingURL: session.drawingURL, timesURL: session.strokeTimesURL)
            photos.load(sessionFolder: session.folderURL)
            // Per Siri/Kurzbefehl angelegt: Aufnahme sofort starten.
            if SessionCommands.shared.autoStartSessionID == session.uuid {
                SessionCommands.shared.autoStartSessionID = nil
                startRecording()
            }
            handleCaptureRequest()
        }
        .onChange(of: SessionCommands.shared.pending) { handleCaptureRequest() }
        .onDisappear {
            player.stop()
            notes.saveNow()
        }
        // Watch über Start/Pause/Fortsetzen/Stopp informieren
        .onChange(of: recorder.state) { PhoneWatchLink.shared.publishState() }
        // Zugeklappt: beim Start direkt in den Schnell-Modus, nach dem Stopp zurück zu den Notizen.
        .onChange(of: recorder.state) { old, new in
            if old == .idle && new != .idle && isCompact { pane = .quick }
            if new == .idle && pane == .quick { pane = .notes }
        }
    }

    /// Umschalter auf schmalem Bildschirm; „Schnell“ nur während der Aufnahme.
    private var panePicker: some View {
        Picker("Ansicht", selection: $pane) {
            ForEach(CompactPane.allCases.filter { $0 != .quick || isRecordingActive }) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var mainContent: some View {
            if isPlaybackMode {
                PlayerBar(player: player)
            } else {
                RecorderBar(recorder: recorder, isListening: transcript.status == .listening,
                            startDisabled: isStarting,
                            onStart: startRecording, onStop: finishRecording, onMarker: { addPhoneMarker() })
            }

            if recorder.isInputSilent {
                SilentMicBanner()
            }

            TranscriptStatusView(status: transcript.status)

            if !markers.markers.isEmpty {
                MarkerListView(markers: markers.markers,
                               onSelect: isPlaybackMode ? { jump(toTime: $0.time) } : nil,
                               onDelete: { markers.remove($0, savingTo: session.markersURL) })
            }

            if !photos.photos.isEmpty {
                PhotoStripView(store: photos) { selectedPhoto = $0 }
            }

            if let message = recorder.errorMessage ?? player.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            }

            if isCompact {
                panePicker
            }

            SessionWorkspace(notes: notes,
                             transcript: transcript,
                             isPlaybackMode: isPlaybackMode,
                             playbackTime: isPlaybackMode ? player.currentTime : nil,
                             highlightTime: isPlaybackMode && player.isPlaying ? player.currentTime : nil,
                             timeForStroke: strokeTime(for:),
                             onJump: jump(toTime:),
                             onSelectSegment: isPlaybackMode ? jump(to:) : nil,
                             compactPane: pane)
    }

    private var cameraMenu: some View {
        Menu {
            Button("Foto aufnehmen", systemImage: "camera") { openCapture(scanner: false) }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            Button("Folie scannen", systemImage: "doc.viewfinder") { openCapture(scanner: true) }
                .disabled(!SlideScanner.isSupported)
        } label: {
            Label("Foto", systemImage: "camera")
        }
        .disabled(isStarting)
    }

    /// Foto/Folie per Siri oder Kurzbefehl – nur in der Session, die gerade aufnimmt.
    private func handleCaptureRequest() {
        guard isRecordingActive, !isCameraShown, !isScannerShown else { return }
        let commands = SessionCommands.shared
        if commands.take(.photo) { openCapture(scanner: false) }
        else if commands.take(.slide) { openCapture(scanner: true) }
    }

    /// Zeitpunkt merken, an dem die Kamera geöffnet wird – das ist der Moment, den man festhalten will.
    private func openCapture(scanner: Bool) {
        captureTime = currentSessionTime()
        if scanner { isScannerShown = true } else { isCameraShown = true }
    }

    private func currentSessionTime() -> TimeInterval? {
        if recorder.state != .idle { return recorder.sessionTime(at: .now) }
        if isPlaybackMode { return player.currentTime }
        return nil
    }

    /// Folien speichern und anschließend den Text erkennen (on-device).
    private func addSlides(_ pages: [UIImage]) {
        let languages = [session.language, "en-US", "de-DE"]
        for page in pages {
            guard let photo = photos.add(page, kind: .slide, time: captureTime) else { continue }
            let store = photos
            Task {
                let text = await TextRecognizer.recognizeText(in: page, languages: languages)
                store.setRecognizedText(text, for: photo.id)
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            Picker("Sprache der Transkription", selection: $session.language) {
                ForEach(TranscriptionLanguage.allCases) { Text($0.label).tag($0.rawValue) }
            }
        } label: {
            Label(TranscriptionLanguage(rawValue: session.language)?.shortLabel ?? "Sprache", systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
        .disabled(isStarting)
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
            if started {
                attachWatch()
            } else if let live {
                await live.finish()
                transcriber = nil
                transcript.status = .idle
            }
        }
    }

    private func finishRecording() {
        PhoneWatchLink.shared.detach()
        notes.saveNow()
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
        jump(toTime: segment.start)
    }

    private func jump(toTime time: TimeInterval) {
        player.seek(to: time)
        if !player.isPlaying { player.toggle() }
    }

    /// Macht die laufende Aufnahme für die Watch (Rewind, Marker, Status) erreichbar.
    private func attachWatch() {
        let recorder = recorder, transcript = transcript, markers = markers
        let session = session
        let markersURL = session.markersURL
        PhoneWatchLink.shared.attach(.init(
            title: { session.title },
            state: {
                switch recorder.state {
                case .idle: .idle
                case .recording: .recording
                case .paused: .paused
                }
            },
            elapsed: { recorder.elapsed },
            recentText: { seconds in transcript.recentText(seconds: seconds, until: recorder.elapsed) },
            addMarker: { markers.add($0, savingTo: markersURL) },
            pause: { recorder.pause() },
            resume: { recorder.resume() },
            stop: { finishRecording() }
        ))
    }

    /// Session-Zeit für einen neuen Pencil-Strich: während der Aufnahme die Aufnahmezeit
    /// beim Schreiben, in der Wiedergabe die aktuelle Abspielposition, sonst keine.
    private func strokeTime(for date: Date) -> TimeInterval? {
        if recorder.state != .idle { return recorder.sessionTime(at: date) }
        if isPlaybackMode { return player.currentTime }
        return nil
    }

    /// Setzt einen ⭐-Marker an der aktuellen Stelle und liefert dessen Zeit.
    @discardableResult
    private func addPhoneMarker() -> TimeInterval? {
        guard let marker = PhoneWatchLink.shared.makeMarker(seconds: WatchProtocol.defaultSeconds, source: .phone) else { return nil }
        markers.add(marker, savingTo: session.markersURL)
        return marker.time
    }
}

/// Schmale Aufnahme-Leiste: Start bzw. Pause/Fortsetzen · Zeit + Pegel · ⭐ · Stopp.
private struct RecorderBar: View {
    let recorder: AudioRecorder
    let isListening: Bool
    let startDisabled: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onMarker: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            switch recorder.state {
            case .idle:
                Button(action: onStart) {
                    Label("Aufnahme starten", systemImage: "record.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(startDisabled)
            case .recording, .paused:
                let recording = recorder.state == .recording
                CircleButton(systemImage: recording ? "pause.fill" : "record.circle.fill",
                             tint: recording ? .orange : .red,
                             label: recording ? "Pause" : "Fortsetzen",
                             action: recording ? recorder.pause : recorder.resume)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(recorder.elapsed.clockString)
                            .font(.title3.monospacedDigit().bold())
                        if isListening {
                            Image(systemName: "captions.bubble.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Live-Transkription läuft")
                        }
                        if !recording {
                            Text("Pause").font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }
                    LevelMeterBar(level: recorder.level).frame(height: 6)
                }
                CircleButton(systemImage: "star.fill", tint: .yellow, label: "Marker setzen", action: onMarker)
                CircleButton(systemImage: "stop.fill", tint: .gray, label: "Beenden", action: onStop)
            }
        }
    }
}

/// Schmale Wiedergabe-Leiste: −15 s · Play/Pause · +15 s · Zeitleiste.
private struct PlayerBar: View {
    let player: AudioPlayer

    var body: some View {
        HStack(spacing: 10) {
            CircleButton(systemImage: "gobackward.15", tint: .secondary, label: "15 s zurück") { player.skip(by: -15) }
            CircleButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", tint: .accentColor,
                         label: player.isPlaying ? "Pause" : "Abspielen", action: player.toggle)
            CircleButton(systemImage: "goforward.15", tint: .secondary, label: "15 s vor") { player.skip(by: 15) }
            VStack(spacing: 0) {
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 0.1))
                HStack {
                    Text(player.currentTime.clockString)
                    Spacer()
                    Text(player.duration.clockString)
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Hinweis, wenn das Mikrofon seit ein paar Sekunden exakt Stille liefert.
private struct SilentMicBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mikrofon liefert kein Signal").font(.callout.bold())
                Text("Ist das iPhone mit dem Mac verbunden (Device Hub, Bildschirmübertragung)? Dann wird das Mikrofon umgeleitet – Verbindung trennen.")
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "mic.slash.fill")
        }
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}


private struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
