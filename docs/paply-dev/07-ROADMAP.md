# paply.dev - Implementation Roadmap

## Phase 1: Foundation (Woche 1-2)

### 1.1 Projekt Setup
- [ ] Neues Repo `paply-dev` erstellen
- [ ] Monorepo-Struktur: `browser-ext/` + `dashboard/` + `supabase/` + `shared/`
- [ ] Turborepo / npm workspaces konfigurieren
- [ ] TypeScript, ESLint, Prettier Setup
- [ ] Shared Types Package (`shared/types.ts`)

### 1.2 Supabase Setup
- [ ] Supabase Projekt erstellen
- [ ] Auth konfigurieren (Email, GitHub OAuth, Google OAuth)
- [ ] Database Schema (Migration 001): alle Tabellen
- [ ] RLS Policies (Migration 002)
- [ ] Storage Bucket `issue-attachments` (Migration 003)
- [ ] Edge Function: `/transcribe` (Groq Whisper)
- [ ] Edge Function: `/structure-issue` (Groq Llama)

### 1.3 Chrome Extension Scaffold
- [ ] Manifest V3 + Vite + React + Tailwind + Shadcn/UI
- [ ] Build-Pipeline (Vite Multi-Entry)
- [ ] Content Script Grundstruktur
- [ ] Background Service Worker Grundstruktur
- [ ] Popup Shell + Routing
- [ ] Side Panel Shell
- [ ] Supabase Client Integration (chrome.storage adapter)

---

## Phase 2: Core Capture (Woche 2-3)

### 2.1 Content Script Capture
- [ ] Console Log Capture (error, warn, log, info)
- [ ] Network Request Capture (PerformanceObserver)
- [ ] System Info Collection
- [ ] Message Handler für Background Script

### 2.2 Screenshot
- [ ] Visible Tab Capture (`chrome.tabs.captureVisibleTab`)
- [ ] Crop Overlay (Content Script Injection)
- [ ] Full Page Capture (Scroll + Stitch)

### 2.3 Annotation Editor
- [ ] Canvas-basierter Editor im Side Panel
- [ ] Rechteck-Tool
- [ ] Pfeil-Tool
- [ ] Freihand-Tool
- [ ] Blur-Tool
- [ ] Toolbar (Tool-Auswahl, Farbe, Größe)
- [ ] Undo/Redo

---

## Phase 3: Voice + AI (Woche 3-4)

### 3.1 Voice Recording
- [ ] getUserMedia Audio Capture im Side Panel
- [ ] MediaRecorder (WebM Opus)
- [ ] Recording UI (Timer, Stop Button)
- [ ] Live-Transkription Anzeige

### 3.2 Transkription
- [ ] Audio → Supabase Edge Function → Groq Whisper
- [ ] Ergebnis in Side Panel anzeigen
- [ ] Error Handling (Retry, Fallback)

### 3.3 AI Issue-Strukturierung
- [ ] Transkription + Captures → Edge Function → Groq Llama
- [ ] Prompt Engineering für Bug-Report-Struktur
- [ ] Ergebnis als editierbares Formular im Side Panel
- [ ] Sprach-Auto-Detect (DE/EN)

---

## Phase 4: Issue Tracker Integration (Woche 4-5)

### 4.1 GitHub Integration
- [ ] GitHub OAuth App erstellen
- [ ] OAuth Flow (Extension → Dashboard Callback → Token speichern)
- [ ] Repos auflisten
- [ ] Issue erstellen (REST API)
- [ ] Screenshot als Markdown-Bild einbetten
- [ ] Console Logs + Network Requests im Issue Body
- [ ] Labels mappen

### 4.2 Linear Integration
- [ ] Linear OAuth App erstellen
- [ ] OAuth Flow
- [ ] Teams + Projects auflisten
- [ ] Issue erstellen (GraphQL)
- [ ] Priority Mapping (Severity → Linear Priority)
- [ ] Screenshot einbetten

### 4.3 Issue Speicherung
- [ ] Issue in Supabase DB speichern
- [ ] Attachments in Supabase Storage hochladen
- [ ] Captures (Console, Network, System) speichern
- [ ] External Issue URL + ID verlinken

---

## Phase 5: Web Dashboard (Woche 5-6)

### 5.1 Dashboard Setup
- [ ] Next.js 15 + React 19 + Tailwind + Shadcn/UI
- [ ] Supabase Auth (SSR mit Middleware)
- [ ] Layout: Sidebar Navigation
- [ ] Docker Setup für Deployment

### 5.2 Auth Pages
- [ ] Login (GitHub, Google, Email)
- [ ] Workspace erstellen (Onboarding)
- [ ] Invite akzeptieren

### 5.3 Issue-Übersicht
- [ ] Issue-Liste mit Thumbnails
- [ ] Filter (Tracker, Severity, Zeitraum)
- [ ] Suche
- [ ] Pagination

### 5.4 Issue Detail
- [ ] Screenshot-Ansicht (mit Annotationen)
- [ ] Alle Felder anzeigen
- [ ] Console Logs (collapsible)
- [ ] Network Requests (collapsible)
- [ ] System Info
- [ ] Link zum externen Issue

### 5.5 Team Management
- [ ] Mitglieder-Liste
- [ ] Einladungslink generieren
- [ ] Rollen verwalten (Owner, Admin, Member)

### 5.6 Settings
- [ ] Profil-Einstellungen
- [ ] Integration verbinden/trennen
- [ ] Standard-Tracker + Repo
- [ ] Rewind Domains verwalten
- [ ] API Key (Groq)

---

## Phase 6: Screen Recording + Rewind (Woche 6-7)

### 6.1 Screen Recording
- [ ] `chrome.tabCapture` für Tab Recording
- [ ] MediaRecorder für Video
- [ ] Floating Timer/Controls
- [ ] Pause/Resume
- [ ] Video in Supabase Storage speichern
- [ ] Video-Preview im Issue

### 6.2 Rewind
- [ ] DOM Snapshot Capture (alle 500ms)
- [ ] Ring Buffer (2 Minuten)
- [ ] Per-Domain Aktivierung (max 3)
- [ ] Timeline/Scrubber UI
- [ ] DOM Replay Preview
- [ ] Snapshot → Screenshot Konvertierung

---

## Phase 7: Polish & Launch (Woche 7-8)

### 7.1 UX Polish
- [ ] Dark Mode / Light Mode
- [ ] Keyboard Shortcuts (`chrome.commands`)
- [ ] Erfolgs-Animationen
- [ ] Loading States
- [ ] Error Handling überall
- [ ] Onboarding-Tour

### 7.2 Performance
- [ ] Extension Bundle-Size optimieren
- [ ] Content Script Footprint minimieren
- [ ] Lazy Loading für Side Panel
- [ ] Supabase Query Optimierung

### 7.3 Testing
- [ ] Extension E2E Tests (Playwright?)
- [ ] API Edge Function Tests
- [ ] Dashboard Component Tests

### 7.4 Launch
- [ ] Chrome Web Store Listing erstellen
- [ ] Screenshots + Video für Store
- [ ] paply.dev Landing Page
- [ ] Deployment auf eigenem Server
- [ ] DNS + SSL für paply.dev
- [ ] In paply Desktop-App Verweis auf paply.dev einbauen

---

## Technische Entscheidungen (Zusammenfassung)

| Entscheidung | Wahl | Begründung |
|-------------|------|------------|
| Repo | Separates Repo | Eigenes Produkt, eigenes Deployment |
| Tech Stack Extension | React + Vite + Tailwind + Shadcn/UI | Gleich wie paply, Wiederverwendbarkeit |
| Tech Stack Dashboard | Next.js + Supabase | SSR Auth, schnelle Entwicklung |
| Backend | Supabase Full Stack | Auth + DB + Storage + Edge Functions in einem |
| Voice | In Extension (Groq Whisper) | Eigenständig, kein paply Desktop nötig |
| Console Capture | Console Override + PerformanceObserver | Kein `chrome.debugger` Warning |
| Annotation | HTML5 Canvas | Leichtgewichtig, keine externe Library |
| Issue-Speicherung | Supabase DB + Tracker | Eigene History + externe Sync |
| Hosting Dashboard | Eigener Server (Docker) | Volle Kontrolle |
| Teams | Von Anfang an (Supabase RLS) | Spart späteres Refactoring |
| Pricing | Erstmal free | Fokus auf Produkt, nicht Monetarisierung |
| Jira | Optional / Later | Komplexer (ADF statt Markdown) |
