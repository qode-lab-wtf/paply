# paply Menubar App

Eigenständige macOS/Windows Menüleisten-App für Sprachtranskription mit Groq Whisper und optional Claude Haiku Polishing.

## Features

- **Tray-Menü** mit:
  - Transcribe (mit konfigurierbarem Shortcut, Standard: ⌥⌘K / Ctrl+Alt+K)
  - History (letzte 30 Transkripte)
  - Einstellungen (API Keys, Polish, Autostart, Shortcut)
  - Nach Updates suchen (Auto-Updater)
  - Über paply
  - Beenden (⌘Q / Ctrl+Q)

- **Direkte API-Calls** zu Groq und Anthropic (kein externer Server nötig)
- **Auto-Paste** ins vorherige Fenster nach Transkription
- **Lokale Speicherung** von Settings und History
- **Auto-Update** über GitHub Releases

## Installation

```bash
cd electron-menubar
npm install
```

## Entwicklung

```bash
npm run dev
```

## Build

### Lokaler Build (ohne Signierung)

```bash
# macOS Apple Silicon
npm run build

# macOS Universal (Intel + Apple Silicon)
npm run build:universal

# Windows x64
npm run build:win

# Alle Plattformen
npm run build:all
```

### Signierter Build mit Auto-Publish (empfohlen für Releases)

```bash
npm run build:publish
```

Dies erzeugt signierte Builds und lädt sie automatisch als GitHub Release hoch.

## Code-Signing & Notarization (macOS)

Für macOS müssen Builds signiert und notarisiert sein, damit Gatekeeper sie nicht blockiert.

### Erforderliche Umgebungsvariablen

| Variable | Beschreibung |
|----------|-------------|
| `CSC_LINK` | Pfad oder Base64 der .p12 Zertifikatsdatei (Developer ID Application) |
| `CSC_KEY_PASSWORD` | Passwort für das Zertifikat |
| `APPLE_ID` | Deine Apple ID E-Mail |
| `APPLE_ID_PASSWORD` | App-spezifisches Passwort (erstellen unter appleid.apple.com) |
| `TEAM_ID` | Deine Apple Developer Team ID |

### Zertifikat erstellen

1. Apple Developer Account (99€/Jahr): https://developer.apple.com
2. Im Developer Portal: Certificates → Create → Developer ID Application
3. Zertifikat herunterladen und in Keychain importieren
4. Als .p12 exportieren mit Passwort

### App-spezifisches Passwort erstellen

1. https://appleid.apple.com → Anmelden
2. Sicherheit → App-spezifische Passwörter → Passwort erstellen
3. Name: "paply Notarization"

### Build mit Signierung

```bash
export CSC_LINK="path/to/certificate.p12"
export CSC_KEY_PASSWORD="your-cert-password"
export APPLE_ID="your@apple.id"
export APPLE_ID_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export TEAM_ID="XXXXXXXXXX"

npm run build:publish
```

## Code-Signing (Windows)

Ohne Code-Signierung zeigt Windows SmartScreen eine Warnung "Windows hat Ihren PC geschützt" an. Nutzer müssen dann auf "Weitere Informationen" → "Trotzdem ausführen" klicken.

### Erforderliche GitHub Secrets

| Secret | Beschreibung |
|--------|-------------|
| `WIN_CSC_LINK` | Base64-kodierte .pfx Zertifikatsdatei |
| `WIN_CSC_KEY_PASSWORD` | Passwort für das Zertifikat |

### Zertifikat kaufen (günstigste Optionen)

| Anbieter | Preis/Jahr | SmartScreen-Vertrauen | Link |
|----------|------------|----------------------|------|
| **Certum Open Source** | ~25€ | Nach einigen Downloads | certum.pl (nur für Open-Source) |
| **Sectigo (Comodo)** | ~70€ | Nach einigen Downloads | sectigo.com |
| **SignPath.io** | Kostenlos | Sofort | signpath.io (nur für Open-Source auf GitHub) |

> ⚠️ **EV-Zertifikate** (300-500€/Jahr) haben sofortiges SmartScreen-Vertrauen, Standard-Zertifikate bauen Reputation erst nach mehreren Downloads auf.

### Zertifikat als Base64 konvertieren

```bash
# macOS/Linux
base64 -i certificate.pfx -o certificate-base64.txt

# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.pfx")) | Out-File certificate-base64.txt
```

### GitHub Secrets einrichten

1. Gehe zu: Repository → Settings → Secrets and variables → Actions
2. Klicke "New repository secret"
3. Erstelle:
   - Name: `WIN_CSC_LINK` → Value: Inhalt von certificate-base64.txt
   - Name: `WIN_CSC_KEY_PASSWORD` → Value: Dein Zertifikats-Passwort

### Kostenlose Alternative: SignPath.io (für Open-Source)

SignPath.io bietet **kostenlose Code-Signierung** für Open-Source-Projekte:

1. Repository muss öffentlich sein auf GitHub
2. Registriere dich auf https://signpath.io
3. Verbinde dein GitHub Repository
4. SignPath signiert automatisch bei jedem Release

**Vorteil:** Sofortiges SmartScreen-Vertrauen, keine Kosten!

## GitHub Release erstellen

Mit gesetzten Umgebungsvariablen:

```bash
# Setzt GH_TOKEN für Upload
export GH_TOKEN="ghp_xxxxxxxxxxxx"

npm run build:publish
```

Dies erstellt automatisch ein GitHub Release mit allen Build-Artefakten und der `latest.yml`/`latest-mac.yml` für den Auto-Updater.

## Einrichtung

1. App starten
2. In Menüleiste klicken → "Einstellungen..."
3. **Groq API Key** eingeben (erforderlich für Transkription)
4. Optional: **Anthropic API Key** für Polish-Funktion
5. Optional: "Polish aktivieren" ankreuzen
6. Speichern

## Nutzung

- **Shortcut drücken** (Standard: ⌥⌘K / Ctrl+Alt+K) → Aufnahme startet
- **Erneut Shortcut drücken** → Aufnahme stoppt, Transkription läuft
- Text wird automatisch ins Clipboard kopiert und (bei aktiviertem Auto-Paste) eingefügt

## Updates

Die App prüft beim Start automatisch auf Updates. Du kannst auch manuell prüfen:
- Tray-Menü → "Nach Updates suchen..."

Bei einem verfügbaren Update wird das Update automatisch heruntergeladen und nach Bestätigung installiert.

## Hinweise

- Bei erstem Start Mikrofon-Berechtigung und ggf. Accessibility-Berechtigung (für Auto-Paste) erteilen
- Die App erscheint NICHT im Dock, nur in der Menüleiste
- **macOS ohne Signierung**: Rechtsklick → Öffnen und Dialog bestätigen, oder im Terminal: `xattr -dr com.apple.quarantine /Applications/paply.app`

## Technische Details

- Electron 33
- electron-store für Settings-Persistenz
- electron-updater für Auto-Updates
- auto-launch für Autostart-Funktion
- Groq Whisper Large V3 Turbo für Transkription
- Claude Haiku 4.5 für optionales Polishing
