# paply.dev - Product Requirements Document

## 1. Produkt-Vision

**paply.dev** ist eine Chrome Extension + Web Dashboard, die es Entwicklern ermöglicht, präzise Dev-Issues per Voice zu erstellen. Der User spricht seinen Bug ein, die Extension erfasst automatisch Screenshot, Console Logs, Network Requests und System-Info, und die AI strukturiert alles zu einem fertigen Issue das direkt an GitHub oder Linear gesendet wird.

**USP:** Voice-first Issue Creation. Kein anderes Tool (BetterBugs, Capture.dev, Jam.dev) bietet Spracheingabe als primären Input.

**Abgrenzung zu paply:** paply = Voice-to-Text Desktop-App (Electron). paply.dev = eigenständiges Produkt (Chrome Extension) für Dev-Issue-Erstellung. Separates Repo, separates Deployment, eigene Identität.

---

## 2. Zielgruppe

- **Primär:** Frontend- und Fullstack-Entwickler die Bugs finden und dokumentieren
- **Sekundär:** QA-Engineers, Product Manager, Designer die Feedback geben
- **Team-Größe:** Kleine bis mittlere Dev-Teams (2-20 Personen)

---

## 3. Kernfeatures

### 3.1 Capture-Modi

| Modus | Beschreibung |
|-------|-------------|
| **Cropped Screenshot** | User zieht Bereich auf der Seite |
| **Visible Tab** | Sichtbarer Tab-Bereich wird erfasst |
| **Full Page** | Gesamte Seite inkl. Scroll-Bereich |
| **Screen Recording** | Tab oder gesamter Bildschirm aufnehmen |
| **Rewind** | Letzte 2 Minuten Browser-Aktivität automatisch aufgezeichnet (pro Domain aktivierbar) |

### 3.2 Annotation-Tools

| Tool | Beschreibung |
|------|-------------|
| **Markierungskasten** | Rechteck um einen Bereich ziehen |
| **Pfeile** | Pfeil auf ein Element zeigen |
| **Freihand-Zeichnen** | Freie Linien/Striche zeichnen |
| **Blur/Verpixeln** | Sensible Daten unkenntlich machen |

- Farben: Rot (default), optional weitere Farben
- Annotation direkt auf dem Screenshot vor dem Absenden

### 3.3 Voice-Eingabe

- Mikrofon-Button in der Extension
- Audio wird per Groq Whisper Large V3 transkribiert (gleiche Technologie wie paply)
- **Nur Code-Modus** - keine weiteren paply-Einstellungen/Agents
- Transkription geht direkt in die AI-Strukturierung

### 3.4 Auto-Capture (technischer Kontext)

Wird automatisch im Hintergrund erfasst und ans Issue angehängt:

- **Console Logs** - Errors, Warnings, Info (letzte 200 Einträge)
- **Network Requests** - URL, Method, Status, Duration, Size
- **System Info** - OS, Browser, Version, Viewport, aktuelle URL
- **Page URL** - Aktuelle Seite wo der Bug auftrat

### 3.5 AI Issue-Strukturierung

Aus Voice-Input + Screenshot + technischem Kontext generiert die AI:

- **Title** - Kurz und prägnant
- **Description** - Was passiert, was erwartet wurde
- **Steps to Reproduce** - Schritte zum Nachstellen
- **Expected Behavior** - Was hätte passieren sollen
- **Actual Behavior** - Was tatsächlich passiert ist
- **Environment** - Automatisch aus System Info
- **Severity** - Vorschlag basierend auf Kontext
- **Labels** - Vorgeschlagene Tags

**Wichtig:** Keine Root-Cause-Analyse. Der Entwickler kümmert sich selbst darum. Die Console-Logs und Network-Daten liefern den nötigen Kontext.

### 3.6 Issue-Tracker-Integrationen

| Tracker | Priorität | Status |
|---------|-----------|--------|
| **GitHub Issues** | Hoch | MVP |
| **Linear** | Hoch | MVP |
| **Jira** | Niedrig | Optional / Later |

- Issues werden in paply.dev gespeichert UND an den Tracker gesendet
- User wählt Ziel-Repo/Projekt vor dem Erstellen
- Screenshot wird als Attachment mitgesendet

### 3.7 Web Dashboard (paply.dev)

- **Issue-Übersicht** - Alle erstellten Issues mit Status, Screenshots, Details
- **Team/Workspace Management** - Mitglieder einladen, Rollen verwalten
- **Integration Settings** - GitHub/Linear verbinden
- **User Settings** - Profil, API Keys, Preferences
- **Issue Detail View** - Vollständige Issue-Ansicht mit allen Captures

### 3.8 Teams/Workspaces

- Von Anfang an eingeplant
- Workspace erstellen, Mitglieder einladen
- Geteilte Integrationen (Team-weites GitHub Repo / Linear Project)
- Supabase Row Level Security (RLS) für Datenisolierung

---

## 4. User Flow

```
1. User browst eine Web-App und findet einen Bug
2. Klickt auf paply.dev Extension Icon (oder Hotkey)
3. Extension Popup öffnet sich:
   a. Wählt Capture-Modus (Screenshot/Recording/Rewind)
   b. Macht Screenshot → Annotation-Editor öffnet sich
   c. Zeichnet Pfeile, Markierungen etc. auf Screenshot
   d. Klickt "Record Bug" → spricht den Bug ein
   e. AI strukturiert Voice + Screenshot + Auto-Captures zum Issue
   f. Issue-Preview wird angezeigt (editierbar)
   g. Wählt Ziel (GitHub Repo / Linear Project)
   h. Klickt "Create Issue"
4. Issue wird in paply.dev gespeichert + an Tracker gesendet
5. Link zum erstellten Issue wird angezeigt + in Clipboard kopiert
```

---

## 5. Nicht im Scope (bewusst ausgelassen)

- Root-Cause-Analyse / AI Debugger
- Mobile App
- Slack/Discord Integration (später möglich)
- Browser-übergreifend (erstmal nur Chrome)
- Pricing / Monetarisierung (erstmal alles free)
- Electron-Integration (paply Desktop bleibt separat)

---

## 6. Erfolgsmetriken

- Issues erstellt pro User pro Woche
- Time-to-Issue (von Extension öffnen bis Issue erstellt)
- Adoption Rate (DAU/WAU)
- Integrationen verbunden pro Workspace

---

## 7. Referenz

- **UI/UX Vorbild:** [BetterBugs.io](https://betterbugs.io)
- **Bestehende Technologie:** paply Electron-App (Groq Whisper Transcription)
