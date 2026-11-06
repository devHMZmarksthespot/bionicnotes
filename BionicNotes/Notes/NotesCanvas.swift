import PencilKit
import SwiftUI

enum NotesMode: String, CaseIterable, Identifiable {
    case write, jump
    var id: String { rawValue }
}

/// Merkt sich, ob ein Apple Pencil benutzt wird. Dann gilt: Pencil schreibt, Finger tippt/scrollt.
enum PencilPreference {
    private static let key = "pencilDetected"

    static var isPencilMode: Bool {
        UIPencilInteraction.prefersPencilOnlyDrawing || UserDefaults.standard.bool(forKey: key)
    }

    static func markPencilDetected() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// PKCanvasView, die bei Größenänderung (Duo auf-/zuklappen) ihre Seitengröße nachzieht.
final class ResizingCanvasView: PKCanvasView {
    var onLayout: ((PKCanvasView) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

/// Erkennt die erste Pencil-Berührung, ohne andere Gesten zu stören.
private final class PencilTouchDetector: UIGestureRecognizer {
    var onPencil: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [UITouch.TouchType.pencil.rawValue as NSNumber]
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onPencil?()
        state = .failed
    }
}

/// Legt einen Schleier über die Seite und lässt nur die Notizen zur aktuellen Stelle frei.
private final class HighlightOverlay: UIView {
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillRule = .evenOdd
        layer.addSublayer(shape)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(holes: [CGRect], veil: UIColor) {
        let path = UIBezierPath(rect: bounds)
        holes.forEach { path.append(UIBezierPath(roundedRect: $0, cornerRadius: 10)) }
        shape.frame = bounds
        shape.path = path.cgPath
        shape.fillColor = veil.cgColor
        if alpha < 1 { UIView.animate(withDuration: 0.25) { self.alpha = 1 } }
    }

    func hide() {
        guard alpha > 0 else { return }
        UIView.animate(withDuration: 0.25) { self.alpha = 0 }
    }
}

/// Endlose PencilKit-Seite mit Werkzeugpalette.
/// - Pencil-Modus (Pencil erkannt): Pencil schreibt immer, Finger-Tipp auf Notiz springt (Wiedergabe).
/// - Ohne Pencil: Umschalter Schreiben/Springen (`mode`).
/// - `highlightTime`: in der Wiedergabe werden Notizen zur aktuellen Stelle freigestellt, der Rest abgedimmt.
struct NotesCanvas: UIViewRepresentable {
    let store: NotesStore
    let pencilMode: Bool
    let mode: NotesMode
    /// Springen erlaubt (nur in der Wiedergabe sinnvoll).
    let jumpEnabled: Bool
    let highlightTime: TimeInterval?
    /// Session-Zeit für einen neuen Strich (nil = ohne Zeitverknüpfung).
    let timeForStroke: (Date) -> TimeInterval?
    let onJump: (TimeInterval) -> Void
    let onPencilDetected: () -> Void

    /// Notizen, die so viele Sekunden vor bis kurz nach der Abspielposition geschrieben wurden, gelten als „aktuell“.
    static let highlightWindow: ClosedRange<TimeInterval> = -8...0.5

    fileprivate struct Config: Equatable {
        let pencilMode: Bool
        let mode: NotesMode
        let jumpEnabled: Bool
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = ResizingCanvasView()
        canvas.drawing = store.drawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .secondarySystemBackground
        canvas.alwaysBounceVertical = true
        canvas.layer.cornerRadius = 12
        canvas.onLayout = { [weak coordinator = context.coordinator] in coordinator?.updateContentSize($0) }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber] // nur Finger
        canvas.addGestureRecognizer(tap)
        context.coordinator.tap = tap

        let detector = PencilTouchDetector(target: nil, action: nil)
        detector.delegate = context.coordinator
        detector.onPencil = { [weak coordinator = context.coordinator] in coordinator?.pencilUsed() }
        canvas.addGestureRecognizer(detector)

        let overlay = HighlightOverlay(frame: .zero)
        canvas.addSubview(overlay)
        context.coordinator.overlay = overlay

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        context.coordinator.toolPicker = picker
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.updateHighlight(canvas, time: highlightTime)

        // Nur bei Änderung anfassen – sonst würde der Canvas bei jedem Update
        // (z. B. Abspielposition) den Fokus vom Titel stehlen.
        let config = Config(pencilMode: pencilMode, mode: mode, jumpEnabled: jumpEnabled)
        guard coordinator.appliedConfig != config else { return }
        coordinator.appliedConfig = config

        let writing: Bool
        if pencilMode {
            canvas.drawingPolicy = .pencilOnly
            writing = true
            coordinator.tap?.isEnabled = jumpEnabled
        } else {
            canvas.drawingPolicy = .anyInput
            writing = !(jumpEnabled && mode == .jump)
            coordinator.tap?.isEnabled = !writing
        }
        canvas.drawingGestureRecognizer.isEnabled = writing
        coordinator.toolPicker?.setVisible(writing, forFirstResponder: canvas)
        // Beim ersten Mal ist der Canvas noch nicht im Fenster → First Responder erst danach.
        if writing { DispatchQueue.main.async { canvas.becomeFirstResponder() } }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: NotesCanvas
        var tap: UITapGestureRecognizer?
        var toolPicker: PKToolPicker?
        var overlay: UIView?
        fileprivate var appliedConfig: Config?
        private var lastHighlight: CGRect?

        init(parent: NotesCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                parent.store.update(canvasView.drawing, timeFor: parent.timeForStroke)
            }
            updateContentSize(canvasView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func pencilUsed() {
            guard !parent.pencilMode else { return }
            PencilPreference.markPencilDetected()
            parent.onPencilDetected()
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

        /// Notizen zur Abspielposition freistellen, Rest abdimmen; bei Bedarf hinscrollen.
        func updateHighlight(_ canvas: PKCanvasView, time: TimeInterval?) {
            guard let overlay = overlay as? HighlightOverlay else { return }
            let rects: [CGRect] = MainActor.assumeIsolated {
                guard let time else { return [] }
                let window = NotesCanvas.highlightWindow
                return parent.store.drawing.strokes.compactMap { stroke in
                    guard let t = parent.store.time(of: stroke),
                          window.contains(t - time) else { return nil }
                    return stroke.renderBounds.insetBy(dx: -12, dy: -12)
                }
            }
            guard !rects.isEmpty else {
                overlay.hide()
                lastHighlight = nil
                return
            }
            let holes = Self.merge(rects)
            canvas.bringSubviewToFront(overlay)
            overlay.show(holes: holes, veil: UIColor.secondarySystemBackground.withAlphaComponent(0.65))

            // Aktuelle Notiz sichtbar halten, aber nur bei neuer Stelle scrollen (Nutzer nicht bekämpfen).
            let union = holes.dropFirst().reduce(holes[0]) { $0.union($1) }
            if lastHighlight != union {
                lastHighlight = union
                let visible = CGRect(origin: canvas.contentOffset, size: canvas.bounds.size)
                if !visible.intersects(union) {
                    canvas.scrollRectToVisible(union.insetBy(dx: 0, dy: -60), animated: true)
                }
            }
        }

        /// Überlappende Rechtecke zusammenfassen (sonst stanzt evenOdd Löcher in Löcher).
        private static func merge(_ rects: [CGRect]) -> [CGRect] {
            var result: [CGRect] = []
            for rect in rects {
                var merged = rect
                var changed = true
                while changed {
                    changed = false
                    if let i = result.firstIndex(where: { $0.intersects(merged) }) {
                        merged = merged.union(result.remove(at: i))
                        changed = true
                    }
                }
                result.append(merged)
            }
            return result
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
            if let overlay, overlay.frame.size != canvas.contentSize {
                overlay.frame = CGRect(origin: .zero, size: canvas.contentSize)
            }
        }
    }
}
