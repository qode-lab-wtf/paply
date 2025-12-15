# paply Roadmap 🎯

> Detaillierte Planung für Features und Verbesserungen  
> Stand: Dezember 2024

---

## Inhaltsverzeichnis

1. [Modi/Agenten-System](#1-modiagenten-system)
2. [Backup & Recovery](#2-backup--recovery)
3. [Design-Überarbeitung](#3-design-überarbeitung)
4. [Cursor-Integration](#4-cursor-integration)
5. [Prompt-Generator](#5-prompt-generator)
6. [Priorisierung & Timeline](#6-priorisierung--timeline)

---

## 1. Modi/Agenten-System

### Problem (Aktuell)
- Keine visuelle Unterscheidung zwischen Modi
- Kein Schnellzugriff via Hotkey zum Modus-Wechsel
- Nur 3 fest definierte Modi (Coding, Meeting, Diktat)
- Modi unterscheiden sich zu wenig in der Ausgabe

### Lösung

#### 1.1 Hotkey-Schnellzugriff für Modi
```
Cmd+1 → Coding-Modus aktivieren
Cmd+2 → Meeting-Modus aktivieren  
Cmd+3 → Diktat-Modus aktivieren
Cmd+4 → Custom Modus 1
...
```
- Visuelle Bestätigung beim Wechsel (kurzes Overlay/Toast)
- Aktueller Modus immer sichtbar im Recording-Fenster

#### 1.2 Agenten-Konfigurator (Custom Modi)

Nutzer können eigene "Agenten" erstellen mit folgenden **9 Hebeln**:

| Hebel | Beschreibung | Optionen |
|-------|--------------|----------|
| **Ton/Stil** | Wie klingt der Output? | Formell, Casual, Technisch, Kreativ |
| **Formatierung** | Wie wird strukturiert? | Fließtext, Bullet Points, Nummerierte Liste, Code-Block, Markdown |
| **Fachbereich** | Welches Vokabular wird erkannt/korrigiert? | Tech/Code, Business, Medizin, Kreativ, Legal, Allgemein |
| **Output-Sprache** | Soll übersetzt werden? | Gleich wie Input, → Englisch, → Deutsch, → Andere |
| **Kreativität (Temperature)** | Wie viel darf ergänzt/interpretiert werden? | 0% (exakt wiedergeben) bis 100% (frei ausschmücken) |
| **Länge** | Komprimieren oder ausbauen? | Kompakt/Zusammenfassung, Normal, Ausführlich/Detailliert |
| **Füllwörter** | Wie streng säubern? | Alle entfernen, Nur störende, Natürlich belassen |
| **Struktur-Erkennung** | Was automatisch markieren? | Action Items, Fragen, Aufgaben, Deadlines, Nichts |
| **Kontext** | Externe Infos einbinden? | Wissensdatenbank, Aktive Dateien, Kein Kontext |

#### 1.3 Beispiel-Agenten (Vorlagen)

**Agent: "Coding"**
```yaml
ton: Technisch
formatierung: Code-Block / Fließtext
fachbereich: Tech/Code
output_sprache: Gleich wie Input
kreativität: 10%
länge: Normal
füllwörter: Alle entfernen
struktur: Nichts
kontext: Aktive Dateien
```

**Agent: "Meeting Notes"**
```yaml
ton: Formell
formatierung: Bullet Points
fachbereich: Business
output_sprache: Gleich wie Input
kreativität: 20%
länge: Kompakt
füllwörter: Alle entfernen
struktur: Action Items, Deadlines
kontext: Keiner
```

**Agent: "Kreativ-Prompt"**
```yaml
ton: Kreativ
formatierung: Fließtext
fachbereich: Kreativ
output_sprache: → Englisch
kreativität: 70%
länge: Ausführlich
füllwörter: Natürlich belassen
struktur: Nichts
kontext: Keiner
```

**Agent: "Social Media"**
```yaml
ton: Casual
formatierung: Fließtext
fachbereich: Allgemein
output_sprache: Gleich wie Input
kreativität: 40%
länge: Kompakt
füllwörter: Nur störende
struktur: Nichts
kontext: Keiner
```

#### 1.4 UI für Agenten-Erstellung (Hybrid-Wizard)

**Konzept:** 4 Schritte mit klickbaren Tabs + Live-Preview

```
┌─────────────────────────────────────────────────────────────────┐
│  Neuer Agent erstellen                              [X Schließen]│
│                                                                  │
│  [●] Grundlagen   [ ] Stil   [ ] Verarbeitung   [ ] Extras      │
│  ════════════════════════════════════════════════════════════   │
│                                                                  │
│  Wie soll dein Agent heißen?                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Social Media Pro                                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Kurze Beschreibung:                                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Optimiert für knackige Social Media Posts                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Icon & Farbe:                                                  │
│  [📱] [🎯] [💬] [✨] [📝]    [🟢] [🟡] [🔵] [🟣]              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ 💡 Tipp: Wähle einen Namen, der den Einsatzzweck        │    │
│  │    beschreibt – so findest du ihn schneller wieder.     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│                                        [← Zurück]  [Weiter →]   │
└─────────────────────────────────────────────────────────────────┘
```

**Schritt 1: Grundlagen**
- Name des Agenten
- Beschreibung (optional)
- Icon auswählen
- Farbe auswählen
- "Von Vorlage starten" Dropdown (Coding, Meeting, Diktat, Leer)

**Schritt 2: Stil & Output**
- Ton/Stil (Formell, Casual, Technisch, Kreativ)
- Formatierung (Fließtext, Bullets, Code, Markdown)
- Länge (Slider: Kompakt ↔ Ausführlich)
- Output-Sprache (Gleich, → Englisch, → Deutsch)

**Schritt 3: Verarbeitung**
- Kreativität/Temperature (Slider: 0% Exakt ↔ 100% Kreativ)
- Füllwörter (Alle entfernen, Nur störende, Belassen)
- Fachbereich (Tech, Business, Kreativ, Medizin, Legal, Allgemein)

**Schritt 4: Extras + Preview**
- Struktur-Erkennung (Checkboxen: Action Items, Fragen, Deadlines)
- Kontext (Dropdown: Keiner, Aktive Dateien, Wissensdatenbank)
- **Live-Preview:**
```
┌─────────────────────────────────────────────────────────────┐
│  Live-Preview                                               │
│  ───────────────────────────────────────────────────────── │
│  Beispiel-Input:                                            │
│  "Ähm also das Meeting war echt produktiv heute ne"         │
│                                                             │
│  Dein Agent würde ausgeben:                                 │
│  "Das Meeting war heute sehr produktiv! 🚀"                 │
└─────────────────────────────────────────────────────────────┘
```

**Abschluss:**
- [Agent erstellen] Button
- Agent erscheint in der Liste
- Hotkey wird automatisch zugewiesen (Cmd+4, Cmd+5, etc.)

**Zusätzliche Features:**
- Import/Export von Agenten (JSON)
- Duplikieren von bestehenden Agenten
- Teilen von Agenten (Zukunft)

---

## 2. Backup & Recovery

### Problem (Aktuell)
- Bei Fehler während/nach Aufnahme ist die Audio verloren
- Nutzer muss 2-3 Minuten Sprechen wiederholen
- Kein Fallback bei API-Fehlern

### Lösung

#### 2.1 Automatisches Audio-Backup
```
Aufnahme startet
    ↓
Audio wird SOFORT lokal zwischengespeichert (temp file)
    ↓
Transkription läuft...
    ↓
┌─ Erfolg? ─────────────────────────────────┐
│  JA → Backup nach 24h automatisch löschen │
│  NEIN → Siehe Recovery-Flow               │
└───────────────────────────────────────────┘
```

#### 2.2 Recovery-Flow bei Fehler

```
Fehler erkannt (Groq API, Netzwerk, etc.)
    ↓
[Automatisch] Erster Retry mit Backup-Audio
    ↓
┌─ Retry erfolgreich? ──────────────────────────────────────┐
│  JA → Normal fortfahren, Nutzer merkt nichts              │
│  NEIN → Fehler-UI anzeigen (siehe unten)                  │
└───────────────────────────────────────────────────────────┘
```

#### 2.3 Fehler-UI im Recording-Fenster

Statt Erfolgs-Haken wird angezeigt:
```
┌─────────────────────────────────────────┐
│                                         │
│            ⚠️ (Warning Icon)            │
│                                         │
│     Verarbeitung fehlgeschlagen         │
│     Audio wurde gesichert               │
│                                         │
│     [Erneut versuchen]  Cmd+Shift+R     │
│                                         │
└─────────────────────────────────────────┘
```

#### 2.4 Manueller Recovery-Shortcut
- **Shortcut:** `Cmd+Shift+R` = Letzte Aufnahme erneut verarbeiten
- Funktioniert auch nachträglich (solange Backup existiert, max 24h)
- Info-Toast: "Letzte Aufnahme wird erneut verarbeitet..."

#### 2.5 Backup-Speicherort
- Temp-Verzeichnis der App
- Format: `backup_[timestamp].webm`
- Auto-Cleanup nach 24 Stunden
- Nur EINE Backup-Datei (letzte Aufnahme)

---

## 3. Design-Überarbeitung

### Problem (Aktuell)
- Zu verspielt, nicht professionell
- Dark Mode als Standard (soll Light Mode sein)
- Schrift zu dick/fett
- Farben (Grün) zu dominant
- Nicht schlank/modern genug

### Lösung

#### 3.1 Design-Prinzipien
- **Light Mode als Standard** (Dark Mode optional)
- **Schlank & Fein** – weniger ist mehr
- **Moderne Typografie** – gut lesbar, nicht fett
- **Dezente Farben** – Akzentfarbe sparsam einsetzen
- **Viel Whitespace** – atmendes Layout

#### 3.2 Typografie
- **Schriftart:** Inter, SF Pro, oder Geist (schlank, modern)
- **Gewichte:** 
  - Headlines: Medium (500)
  - Body: Regular (400)
  - Labels: Regular (400), kleinere Größe
- **Keine fetten/bold Texte** außer bei wichtigen Aktionen

#### 3.3 Farbschema (basierend auf Logo)

**Akzentfarben (aus Logo):**
```css
--accent-primary: #7ED957    /* Grün (Papagei) */
--accent-secondary: #F7D154  /* Gelb (Schnabel) */
```

**Light Mode (Standard):**
```css
--background: #FFFFFF           /* Weiß */
--background-secondary: #F9FAFB /* Sehr helles Grau */
--background-tertiary: #F3F4F6  /* Helles Grau */
--text-primary: #1F2937         /* Dunkelgrau */
--text-secondary: #6B7280       /* Mittelgrau */
--text-muted: #9CA3AF           /* Helles Grau */
--border: #E5E7EB               /* Subtile Border */
--accent: #7ED957               /* Grün für Aktionen */
--accent-hover: #6BC448         /* Grün dunkler */
--success: #7ED957              /* Grün */
--warning: #F7D154              /* Gelb */
```

**Dark Mode (Optional, später):**
```css
--background: #111111
--background-secondary: #1A1A1A
--text-primary: #FAFAFA
--accent: #7ED957
```

#### 3.4 Komponenten-Überarbeitung
- **Sidebar:** Schlanker, weniger Padding
- **Cards:** Subtilere Schatten, dünnere Borders
- **Buttons:** Nicht zu groß, klare Hierarchie
- **Toggles:** Kleiner, feiner
- **Icons:** Outline-Stil, nicht filled

#### 3.5 Recording-Fenster
- Minimalistisch
- Klare Status-Anzeige (Recording, Processing, Done, Error)
- Aktueller Modus sichtbar (klein, dezent)

#### 3.6 Konsistenz App ↔ Website
- Gleiches Design-System für Electron-App und Next.js Website
- Shared CSS Variables / Tailwind Config
- App hat Priorität, Website folgt

---

## 4. Cursor-Integration

### Ziel
Gesprochene Prompts werden automatisch mit relevanten Datei-Tags versehen.

### Lösung

#### 4.1 Screen-Parser
```
Nutzer spricht: "Refactore die Auth-Logik"
    ↓
paply macht Screenshot des aktiven Bildschirms
    ↓
Vision-AI analysiert:
  - Welche Dateien sind sichtbar?
  - Welcher Code ist zu sehen?
  - Gibt es Fehlermeldungen?
    ↓
Output: "Refactore die Auth-Logik @auth.ts @middleware.ts"
```

#### 4.2 Erkennungs-Targets
- Offene Dateien (Tabs)
- Sichtbarer Code im Editor
- Dateibaum (wenn sichtbar)
- Terminal-Output / Fehlermeldungen
- Dateinamen in Code (imports)

#### 4.3 Automatisches Tagging
- Tags werden **automatisch** eingefügt (keine Bestätigung nötig)
- Format: `@dateiname.ext`
- Mehrere Tags möglich
- Nur relevante Dateien (KI-gefiltert)

#### 4.4 Aktivierung
- Eigener Modus: "Cursor-Prompt" oder als Option bei bestehendem Modus
- Oder: Automatisch wenn Cursor im Fokus ist
- Setting: "Screen-Analyse aktivieren" (Privacy-Option)

#### 4.5 Technische Umsetzung
- Screenshot via Electron `desktopCapturer`
- Analyse via Claude Vision oder GPT-4 Vision
- Caching von Dateinamen für Performance
- Optional: MCP-Integration für tiefere Cursor-Anbindung

---

## 5. Prompt-Generator

### Ziel
Gesprochene, grobe Ideen werden zu perfekt formulierten Prompts für KI-Tools.

### Lösung

#### 5.1 Universeller Ansatz
Ein System für alle Tools, mit anpassbarer "Kreativität":

```
Input (DE): "Ein Auto in einer Stadt bei Nacht mit Neonlichtern"
    ↓
Prompt-Generator (Kreativität: 70%)
    ↓
Output (EN): "A sleek futuristic car parked in a bustling cyberpunk 
city at night, neon lights reflecting off wet asphalt, cinematic 
composition, dramatic lighting, highly detailed, photorealistic, 8k"
```

#### 5.2 Kreativitäts-Regler (Temperature)

| Level | Verhalten | Use Case |
|-------|-----------|----------|
| 0-20% | Exakt, nur Grammatik-Fixes | Technische Doku, Code |
| 30-50% | Leichte Ergänzungen, Struktur | Business, E-Mails |
| 60-80% | Kreative Erweiterungen, Details | Grafik-Prompts, Stories |
| 90-100% | Freie Interpretation, viel Ausschmückung | Brainstorming |

#### 5.3 Sprach-Option
- **Setting:** "Output-Sprache" 
- Deutsch sprechen → Englisch ausgeben
- Wichtig für: Midjourney, DALL-E, Stable Diffusion (verstehen EN besser)
- Als Toggle oder Dropdown im Agenten/Modus

#### 5.4 Tool-spezifische Suffixe (Optional)
Für Power-User:
```
[x] Midjourney-Suffix anhängen: --ar 16:9 --v 6 --style raw
[x] Stable Diffusion Tags: masterpiece, best quality, ...
[ ] Custom Suffix: _______________
```

#### 5.5 Zielgruppen (zu recherchieren)
- **Grafiker/Designer** – Bild-Prompts (Midjourney, DALL-E, SD)
- **Writer/Autoren** – Story-Prompts, Charakterbeschreibungen
- **Marketer** – Ad Copy, Social Media Posts
- **Produktmanager** – PRDs, User Stories
- **Weitere** – Community-Feedback einholen

---

## 6. Priorisierung & Timeline

### Phase 1: Foundation (Woche 1-2)
1. **Design-Überarbeitung**
   - Light Mode als Standard
   - Neue Typografie
   - Farbschema
   - Komponenten schlanker machen

### Phase 2: Core Features (Woche 3-4)
2. **Backup & Recovery**
   - Audio-Backup implementieren
   - Recovery-Flow
   - Fehler-UI
   - Shortcut `Cmd+Shift+R`

3. **Modi-Hotkeys**
   - `Cmd+1/2/3` für schnellen Wechsel
   - Visuelle Bestätigung

### Phase 3: Agenten-System (Woche 5-6)
4. **Agenten-Konfigurator**
   - UI für 9 Hebel
   - Preset-Agenten (Coding, Meeting, Diktat, Kreativ)
   - Custom Agenten erstellen

### Phase 4: Advanced (Woche 7-8)
5. **Prompt-Generator**
   - Kreativitäts-Regler
   - Sprach-Übersetzung
   - Tool-Suffixe

### Phase 5: Integration (Woche 9-10)
6. **Cursor-Integration**
   - Screen-Parser
   - Automatisches Tagging
   - Privacy-Settings

---

## Offene Fragen

- [ ] Welche weiteren Zielgruppen sind relevant? (Community-Research)
- [ ] MCP-Integration für Cursor – lohnt sich der Aufwand?
- [ ] Monetarisierung: Welche Features sind Pro?
- [ ] Lokales Whisper als Fallback bei API-Ausfällen?

---

## Notizen

- **Hauptnutzung:** Hotkeys, nicht in der App arbeiten
- **App:** Nur für Settings, Modi, Agenten-Konfiguration
- **USP:** Schnell, unsichtbar, perfekte Ausgabe
- **Ziel:** Professionelles Tool, nicht verspielt

---

## 📝 ChangeLog

### 2024-12-15 – Design-Überarbeitung (Phase 1)

**Status:** ✅ Abgeschlossen

**Änderungen in `dashboard.html`:**

1. **Light Mode als Standard**
   - Hintergrund: Weiß (#FFFFFF) und helles Grau (#F9FAFB)
   - Text: Dunkelgrau (#1F2937) statt Weiß
   - Borders: Subtiles Grau (#E5E7EB)

2. **Neue Farbpalette (aus Logo)**
   - Primär-Akzent: Grün `#7ED957`
   - Sekundär-Akzent: Gelb `#F7D154`
   - Dunkelblau entfernt

3. **Typografie überarbeitet**
   - Schriftart: Inter (Google Fonts)
   - Gewichte reduziert: max 600 statt 700
   - Font-Sizes verkleinert für schlankeren Look

4. **Komponenten verschlankt**
   - Sidebar: 220px statt 240px
   - Padding/Margins reduziert
   - Border-Radius angepasst (10px, 6px)
   - Shadows subtiler (shadow-sm, shadow)

5. **Buttons & Controls**
   - Kleinere Buttons (8px 14px padding)
   - Toggle-Switch: 40x22px statt 44x24px
   - Recording-Button: 72px statt 80px

6. **Cards & Listen**
   - Subtilere Schatten
   - Dünnere Borders
   - Weniger Padding

**Nächste Schritte:**
- [x] ~~Agenten-Tab mit Wizard-UI hinzufügen~~
- [ ] Hotkey-System für Modi-Wechsel (Cmd+1/2/3)
- [ ] Backup-System implementieren

---

### 2024-12-15 – Agenten-Konfigurator (Phase 3)

**Status:** ✅ Abgeschlossen

**Änderungen in `dashboard.html`:**

1. **Navigation umbenannt**
   - "Profile" → "Agenten"
   - Neues Icon (Zahnrad-Stern)

2. **Agenten-Tab komplett neu**
   - Agent-Grid mit Hotkey-Badges (⌘1, ⌘2, ⌘3)
   - "Neuer Agent" Button (dashed border)
   - Aktive Agent-Konfiguration mit:
     - Sprache
     - Output-Sprache
     - Autopaste Toggle
     - Kreativitäts-Slider

3. **Wizard-Modal (4 Schritte)**
   - **Step 1 - Basics:** Name, Beschreibung, Icon-Picker, Farb-Picker
   - **Step 2 - Stil:** Ton (Technisch/Formell/Casual/Kreativ), Fachbereich, Kreativitäts-Slider
   - **Step 3 - Output:** Formatierung, Output-Sprache, Auto-Erkennung (Checkboxen), Autopaste
   - **Step 4 - Preview:** Live-Vorschau, Zusammenfassung, Bestätigung

4. **Neue CSS-Komponenten**
   - Modal-Overlay mit Animation
   - Wizard-Steps mit Progress
   - Icon/Color Picker
   - Option-Cards (2x2 Grid)
   - Checkbox-Group
   - Slider mit Labels
   - Preview-Box

5. **JavaScript-Logik**
   - `openAgentWizard()` / `closeAgentWizard()`
   - `wizardNext()` / `wizardBack()`
   - `goToWizardStep(n)`
   - `updateWizardSummary()` / `updateWizardPreview()`
   - `createAgent()`
   - `selectAgent()` / `updateAgentsUI()`

**Nächste Schritte:**
- [x] ~~Hotkey-System für Modi-Wechsel (Cmd+1/2/3)~~
- [ ] Backup-System implementieren
- [ ] Backend-Anbindung für Custom Agents

---

### 2024-12-15 – Hotkey-System (Phase 2)

**Status:** ✅ Abgeschlossen

**Änderungen:**

1. **electron-main.js**
   - `registerAgentHotkeys()` - Registriert ⌘1, ⌘2, ⌘3 (Mac) / Ctrl+1, Ctrl+2, Ctrl+3 (Win)
   - `switchAgent(agentId)` - Wechselt aktiven Agent und aktualisiert Settings
   - `showAgentSwitchNotification()` - Zeigt Feedback im Recording-Widget
   - Unterstützung für Custom Agents (⌘4, ⌘5, ...)

2. **preload.js**
   - `onAgentSwitched` Listener hinzugefügt

3. **dashboard.html**
   - `showAgentSwitchToast()` - Toast-Notification bei Agent-Wechsel
   - CSS-Animationen für Toast (slideIn/slideOut)
   - IPC-Listener für `agent:switched` Event

4. **recording.html**
   - `showAgentBadge()` - Kurze Badge-Anzeige beim Agent-Wechsel
   - fadeInOut Animation

**Nächste Schritte:**
- [x] ~~Backup-System implementieren~~
- [ ] Backend-Anbindung für Custom Agents

---

### 2024-12-15 – Backup-System (Phase 2)

**Status:** ✅ Abgeschlossen

**Änderungen in `electron-main.js`:**

1. **Backup-Funktionen**
   - `saveAudioBackup(audioData)` - Speichert Audio im RAM
   - `getAudioBackup()` - Holt Backup (mit 24h Expiry-Check)
   - `clearAudioBackup()` - Löscht Backup nach Erfolg
   - `retryLastRecording()` - Verarbeitet Backup erneut

2. **Zentrale Verarbeitungsfunktion**
   - `processAudioData(audioData, isRetry)` - Einheitliche Audio-Verarbeitung
   - Automatisches Backup vor Verarbeitung
   - Backup-Clearing bei Erfolg
   - Backup-Erhalt bei Fehler

3. **Recovery-Hotkey**
   - `⌘⇧R` (Mac) / `Ctrl+Shift+R` (Windows)
   - Verarbeitet letzte Aufnahme erneut
   - Dialog wenn kein Backup verfügbar

**Änderungen in `preload.js`:**
- `onErrorRetry` Event-Listener hinzugefügt

**Änderungen in `recording.html`:**
- Retry-Info Element (`Erneut: ⌘⇧R`)
- CSS für fadeIn Animation
- Error-State zeigt jetzt Retry-Hinweis

**Funktionsweise:**
```
Aufnahme startet
    ↓
Audio wird im RAM gespeichert (Backup)
    ↓
Transkription läuft...
    ↓
┌─ Erfolg? ─────────────────────────────────┐
│  JA → Backup löschen, Text einfügen       │
│  NEIN → Backup behalten, Retry-Hinweis    │
│         ⌘⇧R zum erneuten Verarbeiten      │
└───────────────────────────────────────────┘
```

---

## ✅ Alle geplanten Features implementiert!

**Implementierte Features:**
- [x] Design-Überarbeitung (Light Mode, neue Farben)
- [x] Agenten-Tab mit Wizard-UI
- [x] Hotkey-System (⌘1/2/3 für Agenten)
- [x] Backup-System mit Recovery (⌘⇧R)
- [x] Custom Agents Backend (CRUD, Persistierung, Polishing)
- [x] Prompt-Generator mit Vorlagen für KI-Bildgenerierung
- [x] Cursor-Integration (Screen-Parser mit ⌘⇧S)

**Alle Features der Roadmap sind abgeschlossen! 🎉**

---

## ChangeLog

### 2024-12-15 - Cursor-Integration (Screen-Parser)

**Neue Features:**
- Screen-Capture mit ⌘⇧S (Cmd+Shift+S)
- Claude Vision Analyse des Screenshots
- Automatische Erkennung von:
  - Offene Dateien in Editor-Tabs
  - Aktive Datei
  - Sichtbarer Code
  - Fehlermeldungen
- Datei-Tagging mit @-Prefix für Cursor-Kompatibilität
- Automatische Kontext-Einbindung bei Coding-Agents
- 5-Minuten Cache für Screen-Context

**Hotkeys:**
- ⌘⇧S: Screenshot analysieren und Kontext speichern
- Der Kontext wird automatisch in die nächste Transkription eingebunden

**Technische Details:**
- desktopCapturer für Screen-Capture
- Claude Vision API für Bildanalyse
- captureScreenContext(), analyzeScreenWithVision()
- enhancePromptWithContext() für Prompt-Erweiterung

---

### 2024-12-15 - Prompt-Generator

**Neue Features:**
- Vorlagen-Picker im Agent-Wizard für Schnellstart
- 4 vorkonfigurierte Agent-Templates:
  - 🎨 Bild-Prompt Generator (für Midjourney, DALL-E, Stable Diffusion)
  - 📱 Social Media (für LinkedIn, Twitter, Instagram)
  - 📧 E-Mail Profi (professionelle E-Mails)
  - ✨ Eigener Agent (von Grund auf anpassen)
- Spezieller Prompt-Generator Modus für KI-Bildgenerierung:
  - Automatische Übersetzung ins Englische
  - Professionelle Prompt-Struktur (Subjekt, Stil, Atmosphäre, Details)
  - Einbau von Qualitäts-Keywords (masterpiece, 8k, etc.)
  - Optimale Prompt-Länge (50-150 Wörter)
- isPromptGenerator Flag für Custom Agents

**Technische Details:**
- getPromptGeneratorPrompt() Funktion für spezialisierte Prompts
- Template-Picker UI mit automatischer Formular-Befüllung
- applyTemplate() Funktion für Template-Anwendung

---

### 2024-12-15 - Custom Agents Backend

**Neue Features:**
- Custom Agents werden jetzt persistent gespeichert
- IPC-Handler für CRUD-Operationen (agents:create, agents:update, agents:delete, agents:reorder)
- Dynamische Hotkey-Registrierung für Custom Agents (⌘4, ⌘5, ...)
- Custom Agents erscheinen im Dashboard-Grid mit Delete-Button
- Toast-Benachrichtigungen beim Erstellen/Löschen von Agents
- Vollständiges Polishing-System für Custom Agents mit allen 9 Hebeln:
  - Ton/Stil (technisch, formell, casual, kreativ)
  - Formatierung (Fließtext, Bullet Points, Markdown, Code)
  - Fachbereich (Tech, Business, Creative, Academic)
  - Output-Sprache (gleich, → Englisch, → Deutsch)
  - Kreativität (0-100%)
  - Länge (kurz, mittel, lang)
  - Füllwörter (entfernen/beibehalten)

**Technische Details:**
- electron-main.js: Neue CRUD-Handler, getCustomAgentPrompt() Funktion
- preload.js: Neue API-Methoden exponiert
- dashboard.html: loadCustomAgents(), renderCustomAgents(), showToast()

---

*Dokument wird laufend aktualisiert*
