# BionicNotes – Konzept

Konferenz-App für iPhone + iPad: Audio aufnehmen und **lokal** transkribieren, parallel mit dem Apple Pencil Notizen schreiben, Fotos (iPhone-Kamera oder Meta-Brille) landen automatisch an der richtigen Stelle.

---

## 1. Grundidee: Alles hängt an einer Zeitachse

Jede Session (z. B. ein Vortrag) hat **eine gemeinsame Uhr**, die mit der Aufnahme startet. Alles bekommt einen Zeitstempel:

| Element | Quelle | Zeitstempel |
|---|---|---|
| Audio | Mikrofon (iPhone/iPad, ggf. externes Mikro) | durchgehend |
| Transkript | Apple SpeechAnalyzer (on-device) | pro Wort/Satz |
| Handschrift | PencilKit-Striche | pro Strich |
| Fotos | iPhone-Kamera / Meta-Brille | Aufnahmezeitpunkt |
| Text-Marker | Tap auf „⭐ Wichtig“ | Moment |

Daraus ergibt sich die Killer-Funktion: **Auf einen handschriftlichen Strich oder ein Foto tippen → Audio und Transkript springen genau zu diesem Moment** (wie bei Notability, nur mit Transkript und Brillen-Fotos).

---

## 2. „Duo“: Zwei Betriebsarten

> Hinweis: Den Apple Pencil gibt es nur fürs **iPad** – iPhones unterstützen ihn nicht. Daher eine Universal-App für beide Geräte.

**Modus A – Solo (nur iPad)**
iPad nimmt auf, transkribiert, Pencil-Notizen, Fotos mit iPad-Kamera oder Meta-Brille.

**Modus B – Duo (iPhone + iPad zusammen)** ← empfohlen auf Konferenzen
- **iPhone** = „Aufnahmestation“: Mikrofon, Transkription, Kamera, Verbindung zur Meta-Brille (die Brille ist ohnehin mit dem iPhone gekoppelt).
- **iPad** = „Notizblock“: Pencil-Notizen, Live-Transkript wird angezeigt, Fotos tauchen automatisch auf.
- Verbindung **lokal und ohne Internet** über `MultipeerConnectivity` (Bluetooth/WLAN direkt) – Konferenz-WLAN ist meist unzuverlässig. Später zusätzlich Sync per iCloud (CloudKit).

---

## 3. Funktionsbausteine & Technik

### 3.1 Aufnahme
- `AVAudioEngine` mit Tap → gleichzeitig in Datei schreiben (AAC/m4a) und an die Transkription streamen.
- Hintergrund-Audio-Modus, damit die Aufnahme bei gesperrtem Bildschirm weiterläuft.
- Pause/Fortsetzen, Pegelanzeige, Unterstützung für externe Mikrofone (USB-C, Bluetooth-Lavalier).

### 3.2 Lokale Transkription
- **Primär: Apple `SpeechAnalyzer` + `SpeechTranscriber`** (ab iOS/iPadOS 26), komplett on-device, Deutsch und Englisch unterstützt, schnell, keine Kosten, Sprachmodelle werden vom System geladen (vorab offline laden!).
- Live-Ergebnisse (vorläufig → final) mit Zeitstempeln pro Segment.
- **Optional/Fallback: WhisperKit** (Whisper lokal auf der Neural Engine) – für gemischte Sprachen oder als Nachbearbeitung nach dem Vortrag in höherer Qualität.
- Optional: lokale Zusammenfassung/Stichpunkte mit Apples **Foundation Models** (On-Device-LLM, Apple Intelligence nötig).

### 3.3 Pencil-Notizen
- `PencilKit` (`PKCanvasView`), endlose Seite oder Seiten im A4-Format.
- Jeder Strich hat `creationDate` → Zuordnung zur Audio-Zeitachse.
- Funktionen: Tippen auf Handschrift → Audio-Sprung; Handschrift-Erkennung (Vision) für Suche; Lasso, Radierer, Farben, Text-Boxen.
- Split-View: links Notizen, rechts Live-Transkript (einklappbar).

### 3.4 Fotos – iPhone-Kamera
- Eigene Kamera-Ansicht (`AVCaptureSession`) mit einem Tap, ohne die Notiz zu verlassen.
- Folien-Modus: automatische Perspektivkorrektur (Vision `VNDetectRectanglesRequest` / Dokumentenscanner), OCR des Folientexts → durchsuchbar.

### 3.5 Fotos – Meta-Brille
- **Meta Wearables Device Access Toolkit (DAT)** für iOS, per Swift Package Manager: `github.com/facebook/meta-wearables-dat-ios`.
- Ablauf: `Wearables.configure()` beim Start → Nutzer erteilt Kamera-Berechtigung über die **Meta AI App** → Stream-Session starten → Einzelbild aus dem Stream aufnehmen → Foto mit Zeitstempel in die Session → erscheint automatisch auf dem iPad.
- Auslösen: Button in der App (iPhone/iPad), Apple-Watch-Button oder Lautstärketaste als Fernauslöser. **Zu prüfen:** ob das SDK den Hardware-Auslöser der Brille an Dritt-Apps weitergibt.
- Fallback ohne SDK: Fotos, die normal mit der Brille gemacht und über die Meta AI App in die Fotomediathek importiert werden, per `PhotoKit` anhand des Zeitstempels automatisch der laufenden Session zuordnen.

### 3.6 Nach dem Vortrag
- Session-Ansicht: Zeitleiste mit Audio, Transkript, Notizen, Fotos.
- Volltextsuche über Transkript, Handschrift und Folien-OCR.
- Export: PDF (Notizen + Fotos + Transkript), Markdown, Audio-Datei.
- Ordnerstruktur: Konferenz → Tag → Vortrag (Titel, Sprecher, Raum).

---

## 4. Architektur

```
SwiftUI-App (iOS + iPadOS 26, Universal)
├── Core
│   ├── SessionClock          gemeinsame Zeitachse
│   ├── Datenmodell           SwiftData: Conference, Session, Transcript, Stroke, Photo, Marker
│   └── Storage               Session-Ordner: audio.m4a, drawing.data, photos/, transcript.json
├── Recording                 AVAudioEngine, Hintergrund-Audio
├── Transcription             SpeechAnalyzer (+ optional WhisperKit)
├── Notes                     PencilKit-Canvas, Zeitverknüpfung
├── Capture
│   ├── PhoneCamera           AVFoundation, Folien-Erkennung, OCR
│   └── MetaGlasses           Meta DAT SDK
├── DuoSync                   MultipeerConnectivity (später CloudKit)
└── Export                    PDF, Markdown
```

Alle Daten bleiben lokal auf den Geräten. Keine Cloud-Pflicht.

---

## 5. Was wir brauchen

### Hardware
- **Mac** mit aktuellem macOS und **Xcode 26** (iOS-Apps lassen sich nur auf dem Mac bauen).
- **iPad** mit Apple-Pencil-Unterstützung + passender Pencil.
- **iPhone** (für Duo-Modus und Meta-Brille); für Apple Intelligence/Foundation Models ein iPhone 15 Pro oder neuer.
- **Meta-Brille**, die vom DAT unterstützt wird (Ray-Ban Meta / Oakley Meta – aktuelle Liste in der Meta-Doku prüfen).
- Optional: externes Mikrofon für bessere Transkription in großen Sälen.

### Accounts
- **Apple Developer Program** (99 €/Jahr) – für Geräte-Installation über längere Zeit und TestFlight.
- **Meta Wearables Developer Account** (wearables.developer.meta.com), Organisation + Release Channel anlegen.
- **Meta AI App** auf dem iPhone, Brille gekoppelt, Entwicklermodus aktiviert.

### Software / Bibliotheken
| Zweck | Technologie |
|---|---|
| UI | SwiftUI |
| Daten | SwiftData |
| Audio | AVFoundation / AVAudioEngine |
| Transkription | Speech (SpeechAnalyzer), optional WhisperKit |
| Notizen | PencilKit |
| Kamera / OCR | AVFoundation, Vision, VisionKit |
| Brille | Meta Wearables Device Access Toolkit (iOS) |
| Geräte-Sync | MultipeerConnectivity, später CloudKit |
| Zusammenfassungen | Foundation Models (optional) |

### Berechtigungen (Info.plist)
Mikrofon, Spracherkennung, Kamera, Fotomediathek, Lokales Netzwerk, Bluetooth, Hintergrund-Audio, plus die Einträge, die das Meta-SDK verlangt.

---

## 6. Risiken & offene Punkte

1. **Meta-SDK ist noch Developer Preview.** API kann sich ändern; laut Hinweisen nutzt es aktuell das ExternalAccessory-Framework, was zu **App-Store-Ablehnung** führen kann. Für den eigenen Gebrauch (Xcode-Installation / TestFlight) kein Problem – für eine öffentliche App-Store-Version vorher klären.
2. **Brillen-Auslöser:** unklar, ob Fotos per Tastendruck an der Brille direkt in unsere App gehen oder nur per App-Button. Früh im Prototyp testen.
3. **Akku:** Aufnahme + Live-Transkription + Brillen-Stream über 8 h Konferenztag ist energieintensiv → Brillen-Stream nur bei Bedarf starten, Transkription ggf. erst nachträglich laufen lassen (Einstellung).
4. **Saal-Akustik:** Transkriptionsqualität hängt stark vom Mikrofon ab; externes Mikro oder Platz nahe am Lautsprecher hilft.
5. **Rechtliches:** Mitschnitte von Vorträgen sind oft nur mit Zustimmung erlaubt (DSGVO, Persönlichkeits-/Urheberrecht, Konferenzregeln). Hinweis in der App einbauen.

---

## 7. Umsetzungsplan

| Phase | Inhalt | Ergebnis |
|---|---|---|
| **0 – Spike** (1 Woche) | Meta-DAT-Beispiel-App auf Brille + iPhone zum Laufen bringen, SpeechAnalyzer mit Deutsch testen | Machbarkeit der zwei Risikothemen geklärt |
| **1 – MVP iPad Solo** | Aufnahme, Live-Transkript, PencilKit-Notizen, Zeitverknüpfung, Kamera-Fotos | Erste echte Konferenz nutzbar |
| **2 – Meta-Brille** | DAT-Integration, Foto automatisch in Session, Fallback über Fotomediathek | Brillen-Fotos landen im Notizbuch |
| **3 – Duo-Modus** | iPhone als Aufnahmestation, Multipeer-Sync zum iPad | iPhone + iPad zusammen |
| **4 – Komfort** | Suche, Folien-OCR, PDF-/Markdown-Export, Zusammenfassungen, iCloud-Sync | Rundes Produkt |

---

## 8. Quellen
- Meta Wearables DAT – iOS-Integration: https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/
- Meta Wearables DAT – Übersicht: https://wearables.developer.meta.com/docs/develop/dat/build-overview/
- iOS-SDK auf GitHub: https://github.com/facebook/meta-wearables-dat-ios
- Apple SpeechAnalyzer (WWDC25, Session 277): https://nonstrict.eu/wwdcindex/wwdc2025/277/
- SpeechAnalyzer-Überblick: https://blog.addpipe.com/apple-speechanalyzer-api/
