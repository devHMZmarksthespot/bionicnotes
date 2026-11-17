# BionicNotes 1.0 – TestFlight & App Store

## Stand v1.0

| Bereich | Status |
|---|---|
| Aufnahme, Live-Transkription (DE/EN, on-device) | ✅ |
| Pencil-Notizen mit Zeitsprung, Fotos & Folien-OCR | ✅ |
| ⭐-Marker, Watch-Rewind, Siri/Kurzbefehle | ✅ (Watch: Test auf echter Watch offen) |
| **Genaue Nachtranskription** mit Whisper large-v3 turbo (WhisperKit, on-device, läuft im Hintergrund weiter) + eigene **Fachbegriffe** | ✅ neu |
| **Nachbearbeitung: 10 Vorlagen** (Apple Intelligence on-device, sonst strukturierter Entwurf) | ✅ neu |
| **Export**: PDF, RTF (Word/Pages), Markdown, Text, SRT, Audio, Session-Paket (ZIP) | ✅ neu |
| **Suche** über Titel, Transkript, Folien, Marker, Zusammenfassungen | ✅ neu |
| Einstellungen & Datenschutz (Backup standardmässig aus) | ✅ neu |
| App-Icon | ⚠️ Platzhalter – vor Public Release ersetzen |
| Meta-Brille | ⏭ nicht in 1.0 (SDK Developer Preview, App-Review-Risiko) |

**Datenschutz-Versprechen:** Kein Konto, keine Analytics. Einziger Netzwerkzugriff: das optionale, einmalige Laden
des Whisper-Modells (~630 MB von Hugging Face, `argmaxinc/whisperkit-coreml`) – dabei werden keine Nutzerdaten gesendet. Zusammenfassungen nutzen nur
`SystemLanguageModel` (on-device), **nicht** Private Cloud Compute. Daten verlassen das Gerät nur über Teilen /
In Dateien sichern. Sessions sind standardmässig vom iCloud-/Computer-Backup ausgeschlossen (in den Einstellungen änderbar).

## Upload nach TestFlight

1. **App Store Connect** → Apps → „+" → Neue App
   - Plattform iOS, Name **Bionic Notes**, Primärsprache Deutsch, Bundle-ID `hmzinnovation.bionicnotes`, SKU z. B. `bionicnotes-ios`
2. Mac: `cd bionicnotes && xcodegen && open BionicNotes.xcodeproj` (in **Xcode 27.3 Beta**)
3. Schema **BionicNotes**, Ziel **Any iOS Device (arm64)** → Product › **Archive**
4. Organizer → **Distribute App** → **TestFlight & App Store** → Upload
5. Bei jedem weiteren Upload `CURRENT_PROJECT_VERSION` in `project.yml` erhöhen (Build-Nummer), dann `xcodegen`.
6. Export-Compliance wird nicht abgefragt (`ITSAppUsesNonExemptEncryption = NO`).

> ⚠️ **Beta-SDK:** Mindestversion ist iOS 27.3, gebaut wird mit Xcode 27.3 **Beta**. App Store Connect nimmt
> Builds aus Beta-Xcode in der Regel erst mit dem Release Candidate an. Falls der Upload mit „Unsupported SDK or
> Xcode version" abgelehnt wird: auf den Xcode-27.3-RC warten oder das Deployment Target vorübergehend auf 27.1
> senken (Pencil auf dem Duo braucht 27.2+, der Rest läuft ab 27.1).

**Mac:** Unter App Store Connect › Preise und Verfügbarkeit › „iPhone- und iPad-Apps auf Apple-Silicon-Macs"
aktiviert lassen – dann läuft 1.0 auch auf dem Mac (TestFlight für Mac). Eine eigene macOS-App folgt später.

## App-Store-Texte (Vorschlag)

- **Name:** Bionic Notes
- **Untertitel DE:** Transkript & Protokoll, lokal
- **Untertitel EN:** Private Meeting Transcripts
- **Keywords DE (100 Zeichen):** `Konferenz,Mitschrift,Aufnahme,offline,privat,Zusammenfassung,Meeting,Folien,OCR,Vortrag,Sitzung,KI`
- **Kategorie:** Produktivität (sekundär: Business)
- **App-Datenschutz („Privacy Nutrition Label"):** *Daten werden nicht erfasst*

**Beschreibung (DE, Entwurf):**

> Bionic Notes ist dein Begleiter für Konferenzen, Meetings und Vorlesungen – und alles bleibt auf deinem Gerät.
>
> • Aufnehmen und live transkribieren – direkt auf dem iPhone, ohne Cloud
> • Mit dem Apple Pencil mitschreiben: Tippe auf eine Notiz und hör genau die Stelle, an der du sie geschrieben hast
> • Folien fotografieren – der Text wird erkannt und landet an der richtigen Stelle der Aufnahme
> • ⭐ Wichtige Momente markieren – am iPhone oder an der Apple Watch
> • „Was wurde gerade gesagt?" – die letzten Sekunden als Text auf der Watch
> • Nachbearbeiten mit 10 Vorlagen: Meeting-Protokoll, Bericht, Kurzfassung, Aufgaben & Entscheidungen u. v. m.
> • Exportieren als PDF, Word/Pages, Markdown, Text oder Untertitel
>
> Optimiert für das iPhone Duo – aufgeklappt Notizen und Transkript nebeneinander, zugeklappt der Schnell-Modus.
> Kein Konto, keine Cloud, keine Werbung.

**TestFlight „Was testen":**

> Bitte testen: Aufnahme eines Meetings/Vortrags (Hochdeutsch oder Englisch), Pencil-Notizen, Folien-Scan,
> danach „Nachbearbeiten" (Zauberstab oben rechts): zuerst „Genauer transkribieren", dann verschiedene Vorlagen
> und „Exportieren". Fachbegriffe (Firmen, Produkte) in den Einstellungen eintragen.
> Rückmeldung besonders zur Qualität der Zusammenfassungen.

## Vor dem Public Release

- [ ] Finales App-Icon (1024 px, iOS + watchOS) in `BionicNotes/Assets.xcassets` und `BionicNotesWatch/Assets.xcassets`
- [ ] Screenshots: iPhone 6,9", iPad 13" (+ Duo aufgeklappt, sobald App Store Connect die Grösse anbietet)
- [ ] Datenschutzerklärung-URL (Pflichtfeld) – kurze Seite „Wir erfassen keine Daten"
- [ ] Support-URL
- [ ] Marke „Bionic" im IGE-Register prüfen
- [ ] Modell evtl. über Apple-gehostete Background Assets ausliefern statt Hugging Face
