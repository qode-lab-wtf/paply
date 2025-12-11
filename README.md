# paply – Voice Transcription für Mac

Voice → Groq Whisper Large V3 → Claude Haiku 4.5 polish. Mac-Utility Look, PWA-ready, Dark/Light.

---

## ⬇️ Download (einfach!)

**[paply-1.0.0-arm64.dmg herunterladen](https://github.com/allanhamduws-alt/paply/releases/download/v1.0.0/paply-1.0.0-arm64.dmg)**

1. DMG herunterladen
2. Doppelklick auf die DMG
3. App in den Programme-Ordner ziehen
4. Fertig! ✨

> **Hinweis:** Die App ist nicht signiert. Beim ersten Start: **Rechtsklick → Öffnen → Öffnen bestätigen**.

> **Für Apple Silicon Macs (M1/M2/M3/M4)**

---

## Für Entwickler

<details>
<summary>Klicken für Entwickler-Anleitung</summary>

## Voraussetzungen

**Node.js muss installiert sein!**

1. Prüfe ob Node.js installiert ist:
```bash
node -v
npm -v
```

2. Falls nicht installiert: Lade Node.js von https://nodejs.org (LTS Version) herunter und installiere es.

3. Terminal neu öffnen nach der Installation.

---

## Installation

### 1. Projekt herunterladen

**Option A: Mit Git**
```bash
git clone https://github.com/allanhamduws-alt/paply.git
cd paply
```

**Option B: Als ZIP**
- Download von GitHub → Entpacken → Im Terminal in den Ordner navigieren:
```bash
cd ~/Downloads/paply-main
```

---

### 2. Electron Menubar App (Desktop)

Die Electron-App erscheint in deiner Mac-Menüleiste:

```bash
cd electron-menubar
npm install
npm run dev
```

**Vollständiger Pfad (falls du gerade das Terminal geöffnet hast):**
```bash
cd ~/Downloads/paply-main/electron-menubar
npm install
npm run dev
```

---

### 3. Web Dashboard (optional)

Für die Web-Version brauchst du API-Keys:

1. Erstelle `.env.local` im Hauptordner:
```
GROQ_API_KEY=...
ANTHROPIC_API_KEY=...
```

2. Starte den Dev-Server:
```bash
npm install
npm run dev
```

3. Öffne http://localhost:5173/dashboard

---

## Features

- **Live-Transkription** – MediaRecorder → Chunk-HTTP-POST → Groq Whisper Large V3
- **AI Polish** – Claude Haiku 4.5 mit Tone (Code/Casual/Formal) + FormatHint (Code Block/Bullets)
- **Cmd+K Palette** – Code Block, Bullets, Formal, Start/Stop Recording, Polish
- **Copy + Toast** – „Perfekt für Cursor Agent!", Dark/Light Toggle, DE/EN Toggle
- **PWA manifest** – start_url `/dashboard`, mobile-first Layout

---

## Hinweise

- Groq Whisper nutzt HTTP-Chunk-Uploads (kein WebSocket), ca. 1s-Chunks für optimale Latenz
- Groq ist ~164x schneller als Echtzeit und günstiger als Deepgram bei vergleichbarer Qualität

</details>
