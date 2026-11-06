# BionicNotes

Konferenz-App fürs iPhone Duo + Apple Watch: Aufnahme + lokale Transkription + Apple-Pencil-Notizen + Fotos (iPhone-Kamera / Meta-Brille) + Watch-Rewind.
Mindestversion: iOS / watchOS 27.3 – gebaut mit **Xcode 27.3 Beta**.
Konzept: [docs/KONZEPT.md](docs/KONZEPT.md)

## Projekt auf dem Mac öffnen

Das Xcode-Projekt wird aus `project.yml` erzeugt (mit [XcodeGen](https://github.com/yonaskolb/XcodeGen)), damit es sauber versionierbar bleibt.

```bash
brew install xcodegen          # einmalig
git clone https://github.com/devHMZmarksthespot/bionicnotes.git
cd bionicnotes
git checkout claude/konferenz-app-konzept
xcodegen                       # erzeugt BionicNotes.xcodeproj
open BionicNotes.xcodeproj
```

Bundle-ID (`hmzinnovation.bionicnotes`, Watch: `hmzinnovation.bionicnotes.watchkitapp`) und Team (`CA9847D4GK`) sind in `project.yml` gesetzt.
Xcode-Beta verwenden: `sudo xcode-select -s "/Applications/Xcode-beta 2.app"` oder das Projekt direkt in der Beta öffnen.

Nach jeder Änderung an `project.yml` oder wenn neue Dateien dazukommen: `xcodegen` erneut ausführen.

## Fortschritt

- [x] **Schritt 1** – Grundgerüst: Sessions-Liste, Aufnahme (Pause/Fortsetzen, Pegel, läuft im Hintergrund weiter), Wiedergabe
- [x] Projekt-Setup 27.3 + Watch-Target (Gerüst)
- [x] Schritt 2 – Live-Transkription on-device (SpeechAnalyzer), Transkript antippen → Audio springt
- [~] Watch: BionicNotes Rewind + ⭐ Marker (Simulator-Build, Test auf echter Watch offen) – Fernbedienung folgt
- [x] Schritt 3 – Pencil-Notizen mit Zeitverknüpfung (Tippen auf Notiz → Audio springt)
- [x] Schritt 4 – Fotos mit iPhone-Kamera + Folien-Scan mit OCR
- [ ] Schritt 5 – Layouts auf-/zugeklappt (iPhone Duo)
- [ ] Schritt 6 – Meta-Brille (Wearables Device Access Toolkit)
- [ ] Schritt 7 – Suche, Export, Zusammenfassungen
