# BionicNotes

Konferenz-App fürs iPhone Duo: Aufnahme + lokale Transkription + Apple-Pencil-Notizen + Fotos (iPhone-Kamera / Meta-Brille).
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

Vorher in `project.yml` anpassen:
- `bundleIdPrefix` und `PRODUCT_BUNDLE_IDENTIFIER` → z. B. `com.deinname.bionicnotes`
- `DEVELOPMENT_TEAM` → deine Team-ID (developer.apple.com › Membership)

Nach jeder Änderung an `project.yml` oder wenn neue Dateien dazukommen: `xcodegen` erneut ausführen.

## Fortschritt

- [x] **Schritt 1** – Grundgerüst: Sessions-Liste, Aufnahme (Pause/Fortsetzen, Pegel, läuft im Hintergrund weiter), Wiedergabe
- [ ] Schritt 2 – Live-Transkription on-device (SpeechAnalyzer)
- [ ] Schritt 3 – Pencil-Notizen mit Zeitverknüpfung
- [ ] Schritt 4 – Fotos mit iPhone-Kamera
- [ ] Schritt 5 – Layouts auf-/zugeklappt (iPhone Duo)
- [ ] Schritt 6 – Meta-Brille (Wearables Device Access Toolkit)
- [ ] Schritt 7 – Suche, Export, Zusammenfassungen
