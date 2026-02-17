# paply.dev - Technische Architektur

## 1. Systemübersicht

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   Chrome Extension   │     │   Web Dashboard       │     │   paply Desktop  │
│   (browser-ext/)     │     │   (dashboard/)        │     │   (Verweis)      │
│                      │     │                       │     │                  │
│  - Popup UI          │     │  - Issue-Übersicht    │     │  Link zu         │
│  - Side Panel        │     │  - Team Management    │     │  paply.dev       │
│  - Content Script    │     │  - Settings           │     │                  │
│  - Background SW     │     │  - Issue Detail       │     │                  │
└──────────┬───────────┘     └──────────┬────────────┘     └──────────────────┘
           │                            │
           │         HTTPS              │
           └────────────┬───────────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │   Supabase Backend     │
           │                        │
           │  - Auth (Email, OAuth) │
           │  - PostgreSQL DB       │
           │  - Storage (Bilder)    │
           │  - Edge Functions      │
           │  - Realtime            │
           │  - Row Level Security  │
           └────────────┬───────────┘
                        │
              ┌─────────┼─────────┐
              │         │         │
              ▼         ▼         ▼
         ┌────────┐ ┌───────┐ ┌──────┐
         │ GitHub │ │Linear │ │ Groq │
         │  API   │ │  API  │ │  API │
         └────────┘ └───────┘ └──────┘
```

---

## 2. Tech Stack

### Chrome Extension
| Komponente | Technologie |
|-----------|-------------|
| **Framework** | React 19 + TypeScript |
| **Build** | Vite (Multi-Entry: popup, sidepanel, content, background) |
| **Styling** | Tailwind CSS + Shadcn/UI |
| **State** | Zustand (leichtgewichtig, kein Redux-Overhead) |
| **Audio** | Web Audio API + MediaRecorder |
| **Annotation** | HTML5 Canvas |
| **Storage** | chrome.storage.local |

### Web Dashboard
| Komponente | Technologie |
|-----------|-------------|
| **Framework** | Next.js 15 + React 19 + TypeScript |
| **Styling** | Tailwind CSS + Shadcn/UI |
| **Auth** | Supabase Auth (SSR) |
| **Data Fetching** | Supabase Client + React Query |
| **Deployment** | Eigener Server (Docker) |

### Backend (Supabase)
| Komponente | Technologie |
|-----------|-------------|
| **Auth** | Supabase Auth (Email, GitHub OAuth, Google OAuth) |
| **Database** | PostgreSQL mit RLS |
| **Storage** | Supabase Storage (Screenshots, Recordings) |
| **Edge Functions** | Deno (für Groq API Calls, Issue Tracker APIs) |
| **Realtime** | Supabase Realtime (für Team-Updates) |

---

## 3. Projektstruktur

```
paply-dev/                          # Separates Repo
├── browser-ext/                    # Chrome Extension
│   ├── manifest.json
│   ├── package.json
│   ├── vite.config.ts
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── src/
│   │   ├── background/
│   │   │   └── service-worker.ts
│   │   ├── content/
│   │   │   ├── content-script.ts
│   │   │   ├── console-capture.ts
│   │   │   ├── network-capture.ts
│   │   │   └── rewind-capture.ts
│   │   ├── popup/
│   │   │   ├── index.html
│   │   │   ├── main.tsx
│   │   │   ├── App.tsx
│   │   │   └── components/
│   │   │       ├── CapturePanel.tsx
│   │   │       ├── RecordButton.tsx
│   │   │       ├── IssuePreview.tsx
│   │   │       └── ProviderSelector.tsx
│   │   ├── sidepanel/
│   │   │   ├── index.html
│   │   │   ├── main.tsx
│   │   │   └── components/
│   │   │       ├── IssueEditor.tsx
│   │   │       └── AnnotationCanvas.tsx
│   │   ├── annotation/
│   │   │   ├── AnnotationEditor.tsx
│   │   │   ├── tools/
│   │   │   │   ├── RectangleTool.ts
│   │   │   │   ├── ArrowTool.ts
│   │   │   │   ├── FreehandTool.ts
│   │   │   │   └── BlurTool.ts
│   │   │   └── AnnotationCanvas.ts
│   │   ├── shared/
│   │   │   ├── types.ts
│   │   │   ├── supabase-client.ts
│   │   │   ├── groq-client.ts
│   │   │   └── constants.ts
│   │   └── assets/
│   │       └── icons/
│   └── dist/                       # Build output
│
├── dashboard/                      # Web Dashboard (Next.js)
│   ├── package.json
│   ├── next.config.ts
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── src/
│   │   ├── app/
│   │   │   ├── layout.tsx
│   │   │   ├── page.tsx            # Landing Page
│   │   │   ├── login/
│   │   │   │   └── page.tsx
│   │   │   ├── dashboard/
│   │   │   │   ├── layout.tsx
│   │   │   │   ├── page.tsx        # Issue-Übersicht
│   │   │   │   ├── issues/
│   │   │   │   │   └── [id]/page.tsx
│   │   │   │   ├── settings/
│   │   │   │   │   └── page.tsx
│   │   │   │   └── team/
│   │   │   │       └── page.tsx
│   │   │   └── api/                # API Routes
│   │   │       ├── issues/
│   │   │       │   ├── structure/route.ts
│   │   │       │   └── create/route.ts
│   │   │       └── integrations/
│   │   │           ├── github/route.ts
│   │   │           └── linear/route.ts
│   │   ├── components/
│   │   │   ├── ui/                 # Shadcn/UI
│   │   │   ├── IssueCard.tsx
│   │   │   ├── IssueDetail.tsx
│   │   │   ├── TeamMembers.tsx
│   │   │   └── IntegrationSettings.tsx
│   │   └── lib/
│   │       ├── supabase/
│   │       │   ├── client.ts
│   │       │   ├── server.ts
│   │       │   └── middleware.ts
│   │       ├── integrations/
│   │       │   ├── github.ts
│   │       │   ├── linear.ts
│   │       │   └── types.ts
│   │       └── ai/
│   │           └── structure-issue.ts
│   └── Dockerfile
│
├── supabase/                       # Supabase Config
│   ├── config.toml
│   ├── migrations/
│   │   ├── 001_initial_schema.sql
│   │   ├── 002_rls_policies.sql
│   │   └── 003_storage_buckets.sql
│   └── functions/
│       ├── transcribe/index.ts
│       └── structure-issue/index.ts
│
├── shared/                         # Shared Types/Utils
│   ├── types.ts
│   └── constants.ts
│
├── package.json                    # Root (Workspace)
├── turbo.json                      # Turborepo Config
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## 4. Datenfluss

### Issue-Erstellung (Haupt-Flow)

```
1. Content Script (läuft auf jeder Seite)
   │
   ├── Überschreibt console.error/warn/log → Ring Buffer (200 Einträge)
   ├── PerformanceObserver → Network Requests sammeln
   ├── Rewind: DOM Snapshots alle 500ms (wenn aktiviert)
   │
   ▼
2. User klickt Extension Icon → Popup öffnet sich
   │
   ├── "Screenshot" → Background: chrome.tabs.captureVisibleTab()
   │   └── Annotation Editor öffnet sich (Canvas Overlay)
   │       └── User zeichnet Pfeile, Kästen etc.
   │
   ├── "Record Bug" → navigator.mediaDevices.getUserMedia()
   │   └── MediaRecorder → Audio Chunks
   │
   ▼
3. User klickt "Stop Recording"
   │
   ├── Audio Blob → Supabase Edge Function /transcribe
   │   └── → Groq Whisper API → Transkription zurück
   │
   ├── Content Script sendet: Console Logs + Network Requests + System Info
   │
   ▼
4. Alles zusammen → Supabase Edge Function /structure-issue
   │
   ├── Input: { transcription, screenshot, consoleLogs, networkRequests, systemInfo, url }
   ├── → Groq Llama 3.3 70B → Strukturiertes Issue
   │
   ▼
5. Issue-Preview im Side Panel (editierbar)
   │
   ├── User reviewed Title, Description, Steps, etc.
   ├── Wählt Ziel: GitHub Repo oder Linear Project
   │
   ▼
6. "Create Issue"
   │
   ├── Screenshot → Supabase Storage hochladen
   ├── Issue → Supabase DB speichern
   ├── Issue → GitHub/Linear API erstellen
   │   └── Screenshot als Markdown-Bild einbetten
   │
   ▼
7. Issue URL wird angezeigt + in Clipboard kopiert
```

---

## 5. Deployment

### Chrome Extension
- Build: `cd browser-ext && npm run build` → `dist/` Ordner
- Distribution: Chrome Web Store (manueller Upload oder CI/CD)
- Updates: Chrome Web Store Auto-Update

### Web Dashboard
- Build: Docker Container mit Next.js
- Hosting: Eigener Server (VPS)
- Domain: paply.dev
- SSL: Let's Encrypt / Cloudflare

### Supabase
- Option A: Supabase Cloud (empfohlen für Start - Free Tier reicht)
- Option B: Self-hosted Supabase (später für volle Kontrolle)

---

## 6. Security

- **API Keys** (Groq) leben nur serverseitig (Supabase Edge Functions)
- **User Tokens** (GitHub/Linear) werden verschlüsselt in Supabase DB gespeichert
- **RLS Policies** stellen sicher: User sehen nur eigene/Team-Daten
- **Extension** sendet nie API Keys direkt - alles über Supabase Auth
- **CORS** nur von Extension ID + paply.dev Domain erlaubt
