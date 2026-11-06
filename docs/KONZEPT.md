# BionicNotes – Konzept

Konferenz-App für das **iPhone Duo** (faltbar, Apple Pencil ab iOS 27.2) mit **Apple Watch** und **Meta-Brille**: Audio aufnehmen und **lokal** transkribieren, parallel mit dem Apple Pencil Notizen schreiben, Fotos (iPhone-Kamera oder Meta-Brille) landen automatisch an der richtigen Stelle. Die Watch ist Fernbedienung und zeigt per „Rewind“ das zuletzt Gesagte.

**Der perfekte Konferenztag:** App starten, Aufnahme läuft, man schreibt mit dem Pencil, beobachtet, macht Fotos mit der Brille, holt sich am Handgelenk kurz zurück, was gerade gesagt wurde – und hat am Ende des Vortrags alles Wichtige notiert, mit dem Transkript als Kontext. (Später auch für Schule/Unterricht.)

**Ziel-Release:** zum Public Release von iOS/watchOS 27.3 (Dezember 2026). Mindestversion iOS 27.3 / watchOS 27.3.

---

## 1. Grundidee: Alles hängt an einer Zeitachse

Jede Session (z. B. ein Vortrag) hat **eine gemeinsame Uhr**, die mit der Aufnahme startet. Alles bekommt einen Zeitstempel:

| Element | Quelle | Zeitstempel |
|---|---|---|
| Audio | Mikrofon (iPhone Duo, ggf. externes Mikro) | durchgehend |
| Transkript | Apple SpeechAnalyzer (on-device) | pro Wort/Satz |
| Handschrift | PencilKit-Striche | pro Strich |
| Fotos | iPhone-Kamera / Meta-Brille | Aufnahmezeitpunkt |
| Text-Marker | Tap auf „⭐ Wichtig“ (iPhone oder Watch) | Moment |
| Rewind-Snippet | Watch: „Was wurde gerade gesagt?“ | Moment + letzte 30–60 s |

Daraus ergibt sich die Killer-Funktion: **Auf einen handschriftlichen Strich oder ein Foto tippen → Audio und Transkript springen genau zu diesem Moment** (wie bei Notability, nur mit Transkript und Brillen-Fotos).

---

## 2. Zielgerät: iPhone Duo – alles in einem Gerät

Das iPhone Duo unterstützt seit **iOS 27.2** den **Apple Pencil (USB-C)** (kein Hover, Pencil Pro/ältere Modelle nicht unterstützt). Damit kann ein einziges Gerät alles: Aufnahme, Transkription, Pencil-Notizen, Kamera und die Meta-Brille.

**Zwei Haltungen, zwei Layouts:**
- **Aufgeklappt (Notiz-Modus):** großes Innendisplay → links Pencil-Notizen, rechts Live-Transkript (einklappbar), Foto-Leiste unten.
- **Zugeklappt (Schnell-Modus):** Außendisplay → großer Aufnahme-Status, Marker-Button („⭐ Wichtig“), Foto-Auslöser (Kamera/Brille). Ideal zwischen den Vorträgen oder im Stehen.
- Aufnahme und Transkription laufen beim Auf-/Zuklappen **ohne Unterbrechung** weiter (Scene-Wechsel sauber behandeln, Zustand liegt im App-Kern, nicht in der View).

**Optional später:** iPad als Zweitgerät oder Mac zum Nacharbeiten per iCloud-Sync (CloudKit). Kein Muss mehr.

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
- Aufgeklappt: Split-View links Notizen, rechts Live-Transkript (einklappbar); zugeklappt: Canvas ausgeblendet, nur Schnellfunktionen.
- Pencil-Eingabe ab iOS 27.2 prüfen; ohne Pencil bleibt Finger-Zeichnen/Tippen möglich.

### 3.4 Fotos – iPhone-Kamera
- Eigene Kamera-Ansicht (`AVCaptureSession`) mit einem Tap, ohne die Notiz zu verlassen.
- Folien-Modus: automatische Perspektivkorrektur (Vision `VNDetectRectanglesRequest` / Dokumentenscanner), OCR des Folientexts → durchsuchbar.

### 3.5 Fotos – Meta-Brille
- **Meta Wearables Device Access Toolkit (DAT)** für iOS, per Swift Package Manager: `github.com/facebook/meta-wearables-dat-ios`.
- Ablauf: `Wearables.configure()` beim Start → Nutzer erteilt Kamera-Berechtigung über die **Meta AI App** → Stream-Session starten → Einzelbild aus dem Stream aufnehmen → Foto mit Zeitstempel in die Session → erscheint automatisch in der Notiz an der aktuellen Stelle.
- Auslösen: Button in der App (auch auf dem Außendisplay im zugeklappten Zustand), Apple-Watch-Button oder Lautstärketaste als Fernauslöser. **Zu prüfen:** ob das SDK den Hardware-Auslöser der Brille an Dritt-Apps weitergibt.
- Fallback ohne SDK: Fotos, die normal mit der Brille gemacht und über die Meta AI App in die Fotomediathek importiert werden, per `PhotoKit` anhand des Zeitstempels automatisch der laufenden Session zuordnen.

### 3.6 Apple Watch – Fernbedienung & BionicNotes Rewind
- **Hintergrund:** watchOS 27.3 bringt **Live Rewind** (Digital Crown doppelt drücken → Transkript der letzten 15 s). Das ist eine reine Systemfunktion: **keine API für Dritt-Apps**, nur Englisch, nur Series 12 / Ultra 4 mit iPhone 16+.
- **Unser eigenes Rewind:** Das iPhone transkribiert ohnehin live. Die Watch zeigt auf Tap die **letzten 30–60 s Transkript** – auf Deutsch, mit jeder Watch. Snippet per Tap als Marker in der Session speichern.
- **Fernbedienung:** Aufnahme starten/pausieren, Dauer/Status, „⭐ Wichtig“, Foto auslösen (iPhone-Kamera / Meta-Brille).
- **Technik:** `WatchConnectivity` (`sendMessage` solange die Watch-App aktiv ist, `updateApplicationContext` für den Status). `SpeechAnalyzer` gibt es auf watchOS nicht → Transkription immer auf dem iPhone.
- **Siri / App Intents (Developer Preview in 27.3):** dieselben Aktionen per Sprache („Setz einen Marker“, „Was wurde gerade gesagt?“).
- Optional später: Watch als Zusatzmikrofon für eigene Sprachnotizen.

### 3.7 Nach dem Vortrag
- Session-Ansicht: Zeitleiste mit Audio, Transkript, Notizen, Fotos.
- Volltextsuche über Transkript, Handschrift und Folien-OCR.
- Export: PDF (Notizen + Fotos + Transkript), Markdown, Audio-Datei.
- Ordnerstruktur: Konferenz → Tag → Vortrag (Titel, Sprecher, Raum).

---

## 4. Architektur

```
SwiftUI-App (iOS 27.3+, optimiert für iPhone Duo; läuft auch auf normalen iPhones/iPads)
+ watchOS-App (27.3+): Fernbedienung & Rewind
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
├── WatchLink                 WatchConnectivity, Rewind-Snippets, Fernsteuerung
├── FoldLayout               Layouts für auf-/zugeklappt, nahtloser Wechsel
├── Sync (später)            CloudKit für iPad/Mac
└── Export                    PDF, Markdown
```

Alle Daten bleiben lokal auf den Geräten. Keine Cloud-Pflicht.

---

## 5. Was wir brauchen

### Hardware
- **Mac** mit aktuellem macOS und **Xcode 27.3 (Beta)** mit iOS- und watchOS-27.3-SDK (iOS-Apps lassen sich nur auf dem Mac bauen).
- **iPhone Duo** mit **iOS 27.3** oder neuer.
- **Apple Watch** mit **watchOS 27.3** (Beta lässt sich nicht zurücksetzen – nur Test-Watch).
- **Apple Pencil (USB-C)** – die einzige Pencil-Variante, die das Duo unterstützt.
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
| Falt-Layouts | SwiftUI Size Classes / Scene-Handling |
| Sync (optional) | CloudKit |
| Zusammenfassungen | Foundation Models (optional) |
| Watch | SwiftUI (watchOS), WatchConnectivity |
| Siri | App Intents |

### Berechtigungen (Info.plist)
Mikrofon, Spracherkennung, Kamera, Fotomediathek, Bluetooth, Hintergrund-Audio, plus die Einträge, die das Meta-SDK verlangt.

---

## 6. Risiken & offene Punkte

1. **Meta-SDK ist noch Developer Preview.** API kann sich ändern; laut Hinweisen nutzt es aktuell das ExternalAccessory-Framework, was zu **App-Store-Ablehnung** führen kann. Für den eigenen Gebrauch (Xcode-Installation / TestFlight) kein Problem – für eine öffentliche App-Store-Version vorher klären.
2. **Brillen-Auslöser:** unklar, ob Fotos per Tastendruck an der Brille direkt in unsere App gehen oder nur per App-Button. Früh im Prototyp testen.
3. **Pencil-Einschränkungen:** nur Pencil (USB-C), kein Hover, erst ab iOS 27.2 – Mindestversion 27.3 gesetzt.
7. **Watch:** Apples Live Rewind ist nicht für Apps nutzbar → eigenes Rewind. WatchConnectivity-Übertragungen im Hintergrund sind unzuverlässig → Live-Daten nur bei aktiver Watch-App.
8. **Zeitplan:** Release 27.3 im Dezember ist knapp → Fokus: Transkription, Watch-Rewind, Fernbedienung, Pencil.
4. **Akku:** Aufnahme + Live-Transkription + Brillen-Stream über 8 h Konferenztag ist energieintensiv → Brillen-Stream nur bei Bedarf starten, Transkription ggf. erst nachträglich laufen lassen (Einstellung).
5. **Saal-Akustik:** Transkriptionsqualität hängt stark vom Mikrofon ab; externes Mikro oder Platz nahe am Lautsprecher hilft.
6. **Rechtliches:** Mitschnitte von Vorträgen sind oft nur mit Zustimmung erlaubt (DSGVO, Persönlichkeits-/Urheberrecht, Konferenzregeln). Hinweis in der App einbauen.

---

## 7. Umsetzungsplan

| Phase | Inhalt | Ergebnis |
|---|---|---|
| **0 – Spike** (1 Woche) | Meta-DAT-Beispiel-App auf Brille + iPhone zum Laufen bringen, SpeechAnalyzer mit Deutsch testen | Machbarkeit der zwei Risikothemen geklärt |
| **1 – MVP auf dem Duo** | Aufnahme, Live-Transkript, PencilKit-Notizen, Zeitverknüpfung, Kamera-Fotos, Layouts auf-/zugeklappt | Erste echte Konferenz nutzbar |
| **2 – Meta-Brille** | DAT-Integration, Foto automatisch in Session, Fallback über Fotomediathek | Brillen-Fotos landen im Notizbuch |
| **3 – Außendisplay-Feinschliff** | Schnell-Modus zugeklappt, Watch-Fernauslöser, Marker | Bedienung ohne Aufklappen |
| **4 – Komfort** | Suche, Folien-OCR, PDF-/Markdown-Export, Zusammenfassungen, iCloud-Sync | Rundes Produkt |

---

## 8. Quellen
- iPhone Duo – Apple: https://www.apple.com/iphone-duo/
- iPhone Duo & Apple Pencil ab iOS 27.2 (MacRumors): https://www.macrumors.com/2026/10/21/iphone-duo-apple-pencil-support-ios-27-2/
- Apple Pencil mit iPhone Duo – was zu beachten ist (MacRumors): https://www.macrumors.com/2026/10/23/iphone-duo-apple-pencil/
- Meta Wearables DAT – iOS-Integration: https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/
- Meta Wearables DAT – Übersicht: https://wearables.developer.meta.com/docs/develop/dat/build-overview/
- iOS-SDK auf GitHub: https://github.com/facebook/meta-wearables-dat-ios
- Apple SpeechAnalyzer (WWDC25, Session 277): https://nonstrict.eu/wwdcindex/wwdc2025/277/
- SpeechAnalyzer-Überblick: https://blog.addpipe.com/apple-speechanalyzer-api/
- watchOS 27.3 Live Rewind (MacRumors): https://www.macrumors.com/2026/11/03/watchos-27-3-audio-intelligence/
- watchOS 27.3 Beta (9to5Mac): https://9to5mac.com/2026/11/03/watchos-27-3-beta-adds-new-siri-recap-and-live-rewind-features-for-apple-watch/
- Watch Connectivity: https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity
