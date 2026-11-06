import SwiftUI

/// Schnell-Modus fürs zugeklappte Duo (Außendisplay): große Zeit, Live-Untertitel und
/// große Knöpfe für ⭐, Foto, Folie, Pause und Stopp – bedienbar im Stehen oder zwischen Vorträgen.
struct QuickModeView: View {
    let recorder: AudioRecorder
    let transcript: TranscriptStore
    let isListening: Bool
    let onMarker: () -> TimeInterval?
    let onPhoto: () -> Void
    let onSlide: () -> Void
    let onStop: () -> Void

    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    private var isRecording: Bool { recorder.state == .recording }

    var body: some View {
        VStack(spacing: 14) {
            status
            Text(recorder.elapsed.clockString)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            LevelMeterBar(level: recorder.level)
                .frame(height: 8)

            caption

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    BigButton(title: "Wichtig", systemImage: "star.fill", tint: .yellow, action: setMarker)
                    BigButton(title: isRecording ? "Pause" : "Weiter",
                              systemImage: isRecording ? "pause.fill" : "record.circle.fill",
                              tint: isRecording ? .orange : .red,
                              action: isRecording ? recorder.pause : recorder.resume)
                }
                GridRow {
                    BigButton(title: "Foto", systemImage: "camera.fill", tint: .blue, action: onPhoto)
                    BigButton(title: "Folie", systemImage: "doc.viewfinder", tint: .teal, action: onSlide)
                }
            }

            Button(role: .destructive, action: onStop) {
                Label("Aufnahme beenden", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .overlay(alignment: .top) {
            if let feedback {
                Text(feedback)
                    .font(.callout.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: feedback)
    }

    private var status: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRecording ? Color.red : Color.orange)
                .frame(width: 10, height: 10)
            Text(isRecording ? "Aufnahme läuft" : "Pausiert")
                .font(.headline)
            if isListening {
                Image(systemName: "captions.bubble.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Live-Transkription läuft")
            }
            Spacer()
        }
    }

    /// Live-Untertitel: das zuletzt Gesagte, damit man kurz mitlesen kann.
    private var caption: some View {
        let text = transcript.recentText(seconds: 20, until: recorder.elapsed)
        return Text(text.isEmpty ? "Noch nichts transkribiert …" : "… " + String(text.suffix(160)))
            .font(.callout)
            .foregroundStyle(text.isEmpty ? .tertiary : .secondary)
            .lineLimit(3, reservesSpace: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.default, value: text)
    }

    private func setMarker() {
        guard let time = onMarker() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        feedbackTask?.cancel()
        feedback = "⭐ Marker bei \(time.clockString)"
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { feedback = nil }
        }
    }
}

private struct BigButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(RoundedRectangle(cornerRadius: 18).fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Pegelanzeige (eigene Kopie, da die der Aufnahme-Leiste privat ist).
struct LevelMeterBar: View {
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
