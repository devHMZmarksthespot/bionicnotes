import PencilKit
import SwiftUI

enum NotesMode: String, CaseIterable, Identifiable {
    case write, jump
    var id: String { rawValue }
}

/// PKCanvasView, die bei Größenänderung (Duo auf-/zuklappen) ihre Seitengröße nachzieht.
final class ResizingCanvasView: PKCanvasView {
    var onLayout: ((PKCanvasView) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

/// Endlose PencilKit-Seite mit Werkzeugpalette.
/// - Schreiben: Pencil (oder Finger) zeichnet; jeder Strich bekommt seine Session-Zeit.
/// - Springen: Tippen auf Handschrift ruft `onJump` mit der Zeit dieses Strichs auf.
struct NotesCanvas: UIViewRepresentable {
    let store: NotesStore
    let mode: NotesMode
    /// Session-Zeit für einen neuen Strich (nil = ohne Zeitverknüpfung).
    let timeForStroke: (Date) -> TimeInterval?
    let onJump: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = ResizingCanvasView()
        canvas.drawing = store.drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .secondarySystemBackground
        canvas.alwaysBounceVertical = true
        canvas.layer.cornerRadius = 12
        canvas.onLayout = { [weak coordinator = context.coordinator] in coordinator?.updateContentSize($0) }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        canvas.addGestureRecognizer(tap)
        context.coordinator.tap = tap

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        context.coordinator.toolPicker = picker
        DispatchQueue.main.async {
            context.coordinator.updateContentSize(canvas)
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        // Nur bei Moduswechsel anfassen – sonst würde der Canvas bei jedem Update
        // (z. B. Abspielposition) den Fokus vom Titel-Textfeld stehlen.
        guard context.coordinator.appliedMode != mode else { return }
        context.coordinator.appliedMode = mode
        let writing = mode == .write
        canvas.drawingGestureRecognizer.isEnabled = writing
        context.coordinator.tap?.isEnabled = !writing
        context.coordinator.toolPicker?.setVisible(writing, forFirstResponder: canvas)
        if writing { canvas.becomeFirstResponder() }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: NotesCanvas
        var tap: UITapGestureRecognizer?
        var toolPicker: PKToolPicker?
        var appliedMode: NotesMode?

        init(parent: NotesCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                parent.store.update(canvasView.drawing, timeFor: parent.timeForStroke)
            }
            updateContentSize(canvasView)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let canvas = gesture.view as? PKCanvasView else { return }
            // Im Scroll-View entspricht location(in: canvas) den Content-Koordinaten der Zeichnung.
            let point = gesture.location(in: canvas)
            MainActor.assumeIsolated {
                if let hit = parent.store.timedStroke(at: point) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    parent.onJump(hit.time)
                }
            }
        }

        /// Endlose Seite: immer mindestens eine Bildschirmhöhe Platz unter dem letzten Strich.
        func updateContentSize(_ canvas: PKCanvasView) {
            let width = canvas.bounds.width
            guard width > 0 else { return }
            let bottom = canvas.drawing.bounds.isNull ? 0 : canvas.drawing.bounds.maxY
            let height = max(canvas.bounds.height * 1.5, bottom + canvas.bounds.height)
            if abs(canvas.contentSize.height - height) > 1 || canvas.contentSize.width != width {
                canvas.contentSize = CGSize(width: width, height: height)
            }
        }
    }
}
