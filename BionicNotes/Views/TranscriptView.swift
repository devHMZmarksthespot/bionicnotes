import SwiftUI

/// Transkript einer Session. Live: scrollt mit. Wiedergabe: hebt das aktuelle Segment hervor,
/// Tippen auf ein Segment springt im Audio an diese Stelle.
struct TranscriptView: View {
    let store: TranscriptStore
    /// Abspielposition im Wiedergabe-Modus, sonst `nil` (= Live-Modus).
    let playbackTime: TimeInterval?
    let onSelect: ((TranscriptSegment) -> Void)?

    private var currentID: UUID? {
        playbackTime.flatMap { store.segment(at: $0)?.id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(store.segments) { segment in
                        row(segment, isCurrent: segment.id == currentID)
                            .id(segment.id)
                    }
                    if !store.volatileText.isEmpty {
                        Text(store.volatileText)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .id("volatile")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: store.segments.count) { if playbackTime == nil { scrollToEnd(proxy) } }
            .onChange(of: store.volatileText) { if playbackTime == nil { scrollToEnd(proxy) } }
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(_ segment: TranscriptSegment, isCurrent: Bool) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(segment.start.clockString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
            Text(segment.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isCurrent ? Color.accentColor.opacity(0.15) : .clear))

        if let onSelect {
            Button { onSelect(segment) } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint("Springt im Audio an diese Stelle")
        } else {
            content
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = store.volatileText.isEmpty ? store.segments.last.map { AnyHashable($0.id) } : AnyHashable("volatile")
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
    }
}

/// Kleine Statuszeile über dem Transkript.
struct TranscriptStatusView: View {
    let status: TranscriptStore.Status

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .preparing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Transkription wird vorbereitet …")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text("Sprachmodell wird geladen (einmalig) – \(Int(progress * 100)) %")
                ProgressView(value: progress)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .listening:
            Label("Live-Transkription läuft (on-device)", systemImage: "captions.bubble")
                .font(.callout)
                .foregroundStyle(.green)
        case .unavailable(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
