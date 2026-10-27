# Paply iOS (Phase 0)

Native iPhone-App (SwiftUI) + Paply-Tastatur. V1 kann nur Diktieren und Text einsetzen.
Phase 0 ist ein schlanker, sauber gebauter Prototyp, mit dem auf dem echten iPhone die
riskanten Annahmen gemessen werden – siehe [docs/phase0/TESTPLAN.md](docs/phase0/TESTPLAN.md).

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/` | App `Paply`: Sitzung (Mikro im Hintergrund), Verlauf, Einstellungen, Testseite, Diagnose, Schnelltaste |
| `Keyboard/` | Tastatur `PaplyKeyboard`: nur UIKit, kein Netzwerk, kein PaplyKit |
| `Widgets/` | `PaplyWidgets`: Live Activity (nur während Schnelltasten-Diktat) + Kontrollzentrum-Schalter |
| `Shared/Core/` | für alle drei: App Group, Darwin-Signale, gemeinsamer Zustand, Diagnoseprotokoll, monotone Uhr, Pegel-Datei |
| `Shared/UI/`, `Shared/Intents/` | für App + Widgets: Marke in SwiftUI, Live-Activity-Daten, Intent „Paply-Diktat an/aus“ |
| `PaplyKit/` | Swift Package (Groq, Polieren, Sicherheitsnetz, Audio) – nur in der App |
| `Config/Base.xcconfig` | Bundle-Präfix, App Group, Team, Signierstil |
| `project.yml` | XcodeGen-Spezifikation; `Paply.xcodeproj` ist daraus erzeugt und liegt im Repo |

Bundle-IDs: App = `com.paply.ios`, Tastatur `….keyboard`, Widgets `….widgets`, URL-Schema `paply-ios://` (Tastatur → App).
Das Präfix ist überschreibbar (falls `com.paply.ios` bei Apple schon vergeben ist).

**App Group:** fest `group.com.paply.ios`. Sie steht wörtlich in allen drei `.entitlements`, weil Xcodes
automatisches Signieren eine Variable dort nicht als App Group erkennt. `PAPLY_APP_GROUP` in
`Config/Base.xcconfig` muss zum festen Wert passen (der Code liest ihn aus der Info.plist). Ein anderes
Bundle-Präfix ändert die App Group nicht.

## Bauen und installieren (MacBook)

iPhone per Kabel verbinden, entsperren, „Vertrauen“ bestätigen. Entwicklermodus muss an sein
(Einstellungen → Datenschutz & Sicherheit → Entwicklermodus).

Es reicht eine Kopie des `ios/`-Ordners (kein ganzes Repo nötig); alle Pfade sind relativ zum Skript.

```sh
cd ios
TEAM_ID=ABCDE12345 scripts/device-build.sh --launch
# mit eigenem Präfix bzw. bestimmtem Gerät (Name oder UDID):
TEAM_ID=ABCDE12345 scripts/device-build.sh --prefix de.allan.paply --device "Allans iPhone" --launch
```

Das Skript prüft zuerst, ob Xcode die iOS-Plattform hat (sonst Hinweis auf
`xcodebuild -downloadPlatform iOS`), baut mit `-allowProvisioningUpdates` (Xcode legt App-IDs,
App Group und Profile an), installiert per `xcrun devicectl device install app` und startet optional.
**Phase 0 baut bewusst Debug:** Nur dann lässt sich das Diagnoseprotokoll per `pull-logs.sh` holen
(get-task-allow). `--release` gibt es, ist für die Tests aber nicht gedacht.
Laut Recherche reicht vermutlich auch ein kostenloses Personal Team (Profile dann nur 7 Tage gültig,
höchstens 10 neue App-IDs pro Woche – App, Tastatur und Widgets sind 3).

Danach auf dem iPhone: Einstellungen → Allgemein → Tastatur → Tastaturen → „Tastatur hinzufügen“ →
Paply, dann Paply antippen → „Vollen Zugriff erlauben“. In der App den Groq-Schlüssel eintragen.

## Diagnose holen

```sh
scripts/pull-logs.sh                # bzw. --device "Allans iPhone"
```

Holt `Diagnostics/*.jsonl` aus dem App-Group-Container, schreibt `~/paply-logs/<Zeit>/merged.jsonl`
und zeigt Median und Mittel der Latenzen je Modell · Stücke-Upload · Netz. In der App: Einstellungen → Labor → Diagnose (ansehen, teilen, löschen).
Das Protokoll enthält keine Diktat-Texte, nur Längen und Zeiten.

## Projekt neu erzeugen

Nur nötig, wenn Dateien hinzukommen oder `project.yml` sich ändert:

```sh
xcodegen generate --spec ios/project.yml
```

## Prüfbau ohne iPhone

```sh
xcodebuild -project ios/Paply.xcodeproj -scheme Paply -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/paply-ios-dd CODE_SIGNING_ALLOWED=NO build
```

Auf einem Mac ohne iOS-Plattform-Download (Xcode → Settings → Components) findet Xcode 26
kein Ziel „Any iOS Device“, und `actool` kann den Asset-Katalog ohne Simulator-Laufzeit nicht
übersetzen. Dann so (ohne Schema, Asset-Katalog ausgelassen):

```sh
xcodebuild -project ios/Paply.xcodeproj -target Paply -sdk iphoneos -configuration Debug \
  SYMROOT=/tmp/paply-ios-dd/Build OBJROOT=/tmp/paply-ios-dd/Intermediates \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets build
```

App-Icon neu rendern (im `ios/`-Ordner): `swift scripts/make-app-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
