import SwiftUI
import WatchKit

struct WatchHomeView: View {
    let link: WatchLink
    @State private var markerFeedback: String?
    @State private var isSendingMarker = false

    var body: some View {
        Group {
            if link.state == .idle {
                idleView
            } else {
                recordingView
            }
        }
        .navigationTitle("BionicNotes")
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Keine Aufnahme")
                .font(.headline)
            Text("Starte eine Session auf dem iPhone.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var recordingView: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(link.state == .recording ? Color.red : Color.orange)
                        .frame(width: 8, height: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(link.elapsed(at: context.date).clockString)
                            .font(.title3.monospacedDigit().bold())
                    }
                }
                if !link.title.isEmpty {
                    Text(link.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                NavigationLink {
                    RewindView(link: link)
                } label: {
                    Label("Rewind", systemImage: "gobackward.30")
                        .frame(maxWidth: .infinity)
                }
                .tint(.blue)

                Button {
                    Task { await sendMarker() }
                } label: {
                    Label("Wichtig", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.yellow)
                .disabled(isSendingMarker)

                if let markerFeedback {
                    Text(markerFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func sendMarker() async {
        isSendingMarker = true
        defer { isSendingMarker = false }
        do {
            let snippet = try await link.setMarker(seconds: WatchProtocol.defaultSeconds)
            WKInterfaceDevice.current().play(.success)
            markerFeedback = "⭐ Marker bei \(snippet.time.clockString)"
        } catch {
            WKInterfaceDevice.current().play(.failure)
            markerFeedback = error.localizedDescription
        }
    }
}

/// Zeigt das Transkript der letzten 30 bzw. 60 Sekunden – auch auf Deutsch.
struct RewindView: View {
    let link: WatchLink
    @State private var seconds: TimeInterval = WatchProtocol.defaultSeconds
    @State private var snippet: WatchLink.Snippet?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var savedAt: TimeInterval?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Zeitraum", selection: $seconds) {
                    Text("30 s").tag(30.0)
                    Text("60 s").tag(60.0)
                }
                .pickerStyle(.navigationLink)

                if isLoading && snippet == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if let snippet {
                    Text(snippet.text.isEmpty ? "Noch nichts transkribiert." : snippet.text)
                        .font(.body)
                    Text("bis \(snippet.time.clockString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await saveMarker() }
                } label: {
                    Label(savedAt == nil ? "Als Marker speichern" : "Gespeichert ✓", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.yellow)
                .disabled(snippet == nil || savedAt != nil)

                Button {
                    Task { await load() }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Rewind")
        .task(id: seconds) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snippet = try await link.rewind(seconds: seconds)
            errorMessage = nil
            savedAt = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveMarker() async {
        do {
            let result = try await link.setMarker(seconds: seconds)
            savedAt = result.time
            WKInterfaceDevice.current().play(.success)
        } catch {
            errorMessage = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

