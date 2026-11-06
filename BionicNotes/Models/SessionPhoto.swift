import Foundation
import Observation
import UIKit

/// Foto oder gescannte Folie auf der Session-Zeitachse.
struct SessionPhoto: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case photo, slide }

    var id = UUID()
    /// Sekunden auf der Session-Zeitachse (nil = außerhalb von Aufnahme/Wiedergabe aufgenommen).
    var time: TimeInterval?
    var kind: Kind
    var fileName: String
    /// Erkannter Text (Folien-OCR), für Suche und Export.
    var recognizedText: String?
}

/// Fotos einer Session: photos/<id>.jpg + photos.json im Session-Ordner.
@MainActor
@Observable
final class PhotoStore {
    private(set) var photos: [SessionPhoto] = []
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var thumbnails: [UUID: UIImage] = [:]

    private var indexURL: URL? { folder?.appending(path: "photos.json") }
    private var photosFolder: URL? { folder?.appending(path: "photos", directoryHint: .isDirectory) }

    func load(sessionFolder: URL) {
        folder = sessionFolder
        guard let indexURL, let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([SessionPhoto].self, from: data) else {
            photos = []
            return
        }
        photos = list
    }

    /// Speichert das Bild und liefert den neuen Eintrag.
    @discardableResult
    func add(_ image: UIImage, kind: SessionPhoto.Kind, time: TimeInterval?) -> SessionPhoto? {
        guard let photosFolder, let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        try? FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
        let photo = SessionPhoto(time: time, kind: kind, fileName: UUID().uuidString + ".jpg")
        do {
            try data.write(to: photosFolder.appending(path: photo.fileName), options: .atomic)
        } catch {
            return nil
        }
        photos.append(photo)
        photos.sort { ($0.time ?? .infinity) < ($1.time ?? .infinity) }
        save()
        return photo
    }

    func setRecognizedText(_ text: String, for id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].recognizedText = text
        save()
    }

    func remove(_ photo: SessionPhoto) {
        if let url = url(for: photo) { try? FileManager.default.removeItem(at: url) }
        photos.removeAll { $0.id == photo.id }
        thumbnails[photo.id] = nil
        save()
    }

    func url(for photo: SessionPhoto) -> URL? {
        photosFolder?.appending(path: photo.fileName)
    }

    func image(for photo: SessionPhoto) -> UIImage? {
        url(for: photo).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    func thumbnail(for photo: SessionPhoto) -> UIImage? {
        if let cached = thumbnails[photo.id] { return cached }
        let thumb = image(for: photo)?.preparingThumbnail(of: CGSize(width: 160, height: 160))
        thumbnails[photo.id] = thumb
        return thumb
    }

    private func save() {
        guard let indexURL else { return }
        try? JSONEncoder().encode(photos).write(to: indexURL, options: .atomic)
    }
}
