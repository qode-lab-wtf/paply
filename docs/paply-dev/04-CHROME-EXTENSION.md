# paply.dev - Chrome Extension Spec

## 1. Manifest V3

```json
{
  "manifest_version": 3,
  "name": "paply.dev - Voice Bug Reports",
  "version": "0.1.0",
  "description": "Create dev issues by speaking. Auto-captures console logs, network requests, screenshots.",
  "permissions": [
    "activeTab",
    "tabs",
    "tabCapture",
    "storage",
    "sidePanel"
  ],
  "host_permissions": ["<all_urls>"],
  "background": {
    "service_worker": "background/service-worker.js",
    "type": "module"
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content/content-script.js"],
      "run_at": "document_start",
      "all_frames": false
    }
  ],
  "action": {
    "default_popup": "popup/index.html",
    "default_icon": {
      "16": "icons/icon-16.png",
      "32": "icons/icon-32.png",
      "48": "icons/icon-48.png",
      "128": "icons/icon-128.png"
    }
  },
  "side_panel": {
    "default_path": "sidepanel/index.html"
  },
  "commands": {
    "_execute_action": {
      "suggested_key": {
        "default": "Alt+Shift+B",
        "mac": "Alt+Shift+B"
      },
      "description": "Open paply.dev"
    },
    "quick-screenshot": {
      "suggested_key": {
        "default": "Alt+Shift+S",
        "mac": "Alt+Shift+S"
      },
      "description": "Quick screenshot capture"
    }
  },
  "icons": {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  }
}
```

---

## 2. Komponenten-Architektur

### 2.1 Content Script (`content-script.ts`)

Wird auf jeder Seite injiziert bei `document_start`.

**Verantwortlichkeiten:**
- Console Log Capture (Override vor Page-Scripts)
- Network Request Capture (PerformanceObserver)
- System Info sammeln
- Rewind: DOM Snapshots (wenn aktiviert)
- Screenshot Crop Overlay einblenden (auf Anfrage)

```typescript
// Console Capture
const capturedLogs: ConsoleEntry[] = [];
const MAX_ENTRIES = 200;

const originalConsole = {
  log: console.log,
  warn: console.warn,
  error: console.error,
  info: console.info,
};

['error', 'warn', 'log', 'info'].forEach(level => {
  console[level] = (...args: any[]) => {
    capturedLogs.push({
      level,
      message: args.map(a => {
        try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
        catch { return String(a); }
      }).join(' '),
      timestamp: Date.now(),
      source: new Error().stack?.split('\n')[2]?.trim() || '',
    });
    if (capturedLogs.length > MAX_ENTRIES) capturedLogs.shift();
    originalConsole[level](...args);
  };
});

// Network Capture
const capturedRequests: NetworkEntry[] = [];

const observer = new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    if (entry.entryType === 'resource') {
      const resource = entry as PerformanceResourceTiming;
      capturedRequests.push({
        url: resource.name,
        type: resource.initiatorType,
        duration_ms: Math.round(resource.duration),
        size_bytes: resource.transferSize,
        status: resource.responseStatus || 0,
        timestamp: Date.now(),
      });
      if (capturedRequests.length > MAX_ENTRIES) capturedRequests.shift();
    }
  }
});
observer.observe({ type: 'resource', buffered: true });

// System Info
function getSystemInfo(): SystemInfo {
  return {
    os: navigator.platform,
    browser: navigator.userAgent,
    viewport: { width: window.innerWidth, height: window.innerHeight },
    screen: { width: screen.width, height: screen.height },
    devicePixelRatio: window.devicePixelRatio,
    language: navigator.language,
    url: window.location.href,
  };
}

// Message Handler - Background Script fragt Daten ab
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === 'GET_CAPTURES') {
    sendResponse({
      consoleLogs: [...capturedLogs],
      networkRequests: [...capturedRequests],
      systemInfo: getSystemInfo(),
    });
  }
  if (msg.type === 'SHOW_CROP_OVERLAY') {
    showCropOverlay();  // Injiziert Crop-UI
  }
  if (msg.type === 'GET_REWIND_DATA') {
    sendResponse({ snapshots: rewindBuffer });
  }
  return true;  // Keep channel open for async response
});
```

### 2.2 Rewind Capture

```typescript
// Rewind: DOM Snapshots alle 500ms
// Nur aktiviert wenn User es für die Domain einschaltet
const rewindBuffer: RewindSnapshot[] = [];
const REWIND_DURATION_MS = 2 * 60 * 1000;  // 2 Minuten
const SNAPSHOT_INTERVAL_MS = 500;

let rewindInterval: number | null = null;

function startRewind() {
  rewindInterval = setInterval(() => {
    const snapshot: RewindSnapshot = {
      html: document.documentElement.outerHTML,
      scrollX: window.scrollX,
      scrollY: window.scrollY,
      url: window.location.href,
      timestamp: Date.now(),
    };
    rewindBuffer.push(snapshot);

    // Alte Snapshots entfernen (> 2 Minuten)
    const cutoff = Date.now() - REWIND_DURATION_MS;
    while (rewindBuffer.length > 0 && rewindBuffer[0].timestamp < cutoff) {
      rewindBuffer.shift();
    }
  }, SNAPSHOT_INTERVAL_MS);
}

function stopRewind() {
  if (rewindInterval) {
    clearInterval(rewindInterval);
    rewindInterval = null;
  }
  rewindBuffer.length = 0;
}

// Aktivierung pro Domain über chrome.storage
chrome.storage.local.get('rewindDomains', (result) => {
  const domains = result.rewindDomains || [];
  if (domains.includes(window.location.hostname)) {
    startRewind();
  }
});
```

### 2.3 Background Service Worker (`service-worker.ts`)

**Verantwortlichkeiten:**
- Screenshot Capture (`chrome.tabs.captureVisibleTab`)
- Full Page Screenshot (Scroll + Stitch)
- Screen Recording (`chrome.tabCapture`)
- API Calls an Supabase (Transcribe, Structure, Create)
- Message Routing zwischen Content Script ↔ Popup/SidePanel

```typescript
// Screenshot Capture
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'CAPTURE_VISIBLE_TAB') {
    chrome.tabs.captureVisibleTab(null, { format: 'png' }, (dataUrl) => {
      sendResponse({ screenshot: dataUrl });
    });
    return true;
  }

  if (msg.type === 'CAPTURE_FULL_PAGE') {
    captureFullPage(msg.tabId).then(sendResponse);
    return true;
  }

  if (msg.type === 'START_RECORDING') {
    startTabRecording(msg.tabId).then(sendResponse);
    return true;
  }

  if (msg.type === 'TRANSCRIBE_AUDIO') {
    transcribeAudio(msg.audioBlob).then(sendResponse);
    return true;
  }

  if (msg.type === 'STRUCTURE_ISSUE') {
    structureIssue(msg.data).then(sendResponse);
    return true;
  }

  if (msg.type === 'CREATE_ISSUE') {
    createIssue(msg.data).then(sendResponse);
    return true;
  }
});

// Full Page Screenshot: Scroll + Capture + Stitch
async function captureFullPage(tabId: number): Promise<string> {
  // 1. Get page dimensions via content script
  // 2. Scroll to each viewport-sized section
  // 3. Capture each section with captureVisibleTab
  // 4. Stitch together on OffscreenDocument canvas
  // 5. Return combined dataUrl
}

// Tab Recording
async function startTabRecording(tabId: number) {
  const stream = await chrome.tabCapture.capture({
    video: true,
    audio: true,
    videoConstraints: {
      mandatory: { minWidth: 1920, minHeight: 1080 }
    }
  });
  // MediaRecorder aufsetzen, Chunks sammeln
}
```

### 2.4 Popup UI (`popup/`)

Kompakte UI die sofort beim Klick auf Extension Icon erscheint.

**Layout:**
```
┌──────────────────────────────────┐
│  paply.dev           [Settings]  │
│                                  │
│  ┌──────┐ ┌──────┐ ┌──────┐    │
│  │  📷  │ │  🎬  │ │  ⏪  │    │
│  │Screen│ │Record│ │Rewind│    │
│  │ shot │ │ ing  │ │      │    │
│  └──────┘ └──────┘ └──────┘    │
│                                  │
│  ┌────────────────────────────┐  │
│  │  🎙️ Record Bug (hold)     │  │
│  └────────────────────────────┘  │
│                                  │
│  Target: myorg/frontend ▾       │
│                                  │
│  [Open in Side Panel →]         │
└──────────────────────────────────┘
```

**Interaktionen:**
- Screenshot-Button → Popup schließt kurz, Crop Overlay auf der Seite, Popup öffnet wieder mit Preview
- Recording-Button → Tab-Recording startet, Timer läuft
- Rewind-Button → Zeigt letzte 2 Min, User wählt Clip
- Record Bug → Hält gedrückt = nimmt auf, loslassen = transkribieren
- Target Dropdown → GitHub Repo oder Linear Project auswählen
- Side Panel → Für ausführlicheres Editing

### 2.5 Side Panel (`sidepanel/`)

Persistente UI an der Seite des Browsers für das volle Issue-Editing.

**Layout:**
```
┌──────────────────────────────┐
│  paply.dev Issue Editor      │
│                              │
│  ┌────────────────────────┐  │
│  │  [Screenshot Preview]  │  │
│  │  mit Annotation-Tools  │  │
│  │  □ ↗ ✏️ ▓ │  Farbe ●  │  │
│  └────────────────────────┘  │
│                              │
│  Title                       │
│  ┌────────────────────────┐  │
│  │ Save button broken     │  │
│  └────────────────────────┘  │
│                              │
│  Description                 │
│  ┌────────────────────────┐  │
│  │ When clicking save...  │  │
│  │                        │  │
│  └────────────────────────┘  │
│                              │
│  Steps to Reproduce          │
│  ┌────────────────────────┐  │
│  │ 1. Navigate to /editor │  │
│  │ 2. Make changes        │  │
│  │ 3. Click Save          │  │
│  └────────────────────────┘  │
│                              │
│  Expected / Actual           │
│  ┌────────┐ ┌────────────┐  │
│  │Changes │ │Nothing     │  │
│  │saved   │ │happens     │  │
│  └────────┘ └────────────┘  │
│                              │
│  Severity: [Minor ▾]        │
│  Labels:  [bug] [frontend]  │
│                              │
│  ── Auto-captured ────────── │
│  Console: 3 errors, 1 warn  │
│  Network: 1 failed request   │
│  System: macOS, Chrome 121   │
│  [View Details ▾]           │
│                              │
│  Send to: [GitHub ▾]        │
│  Repo: [myorg/frontend ▾]   │
│                              │
│  [Create Issue]              │
└──────────────────────────────┘
```

---

## 3. Annotation Editor

### Canvas-basierter Editor

Der Annotation Editor wird als Overlay über den Screenshot gelegt (im Side Panel).

**Tools:**

| Tool | Beschreibung | Implementierung |
|------|-------------|-----------------|
| **Rechteck** | Zieht ein Rechteck (Outline) | Canvas `strokeRect()` |
| **Pfeil** | Zieht einen Pfeil von A nach B | Canvas Path mit Pfeilspitze |
| **Freihand** | Zeichnet frei mit dem Cursor | Canvas `lineTo()` auf `mousemove` |
| **Blur** | Verpixelt einen Bereich | Canvas `getImageData()` → Pixelate → `putImageData()` |

**Toolbar:**
```
[□ Rect] [↗ Arrow] [✏️ Draw] [▓ Blur] | [Undo] [Redo] | Farbe: [●] Größe: [─]
```

**Implementierung:**
```typescript
interface AnnotationTool {
  name: string;
  cursor: string;
  onMouseDown(e: MouseEvent, ctx: CanvasRenderingContext2D): void;
  onMouseMove(e: MouseEvent, ctx: CanvasRenderingContext2D): void;
  onMouseUp(e: MouseEvent, ctx: CanvasRenderingContext2D): void;
}

// Annotation State (Undo/Redo)
interface AnnotationState {
  layers: AnnotationLayer[];
  currentLayerIndex: number;
}

interface AnnotationLayer {
  tool: string;
  color: string;
  lineWidth: number;
  points: Point[];     // Für Freihand
  rect?: Rect;         // Für Rechteck/Blur
  arrow?: Arrow;       // Für Pfeil
}
```

**Undo/Redo:** Jede Zeichenaktion wird als Layer gespeichert. Undo entfernt den letzten Layer, Redo stellt ihn wieder her. Bei jeder neuen Aktion: Screenshot neu rendern + alle aktiven Layers darüber zeichnen.

---

## 4. Voice Recording in der Extension

```typescript
// Im Popup oder Side Panel
class VoiceRecorder {
  private mediaRecorder: MediaRecorder | null = null;
  private chunks: Blob[] = [];

  async start(): Promise<void> {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        sampleRate: 16000,
      }
    });

    this.mediaRecorder = new MediaRecorder(stream, {
      mimeType: 'audio/webm;codecs=opus',
      audioBitsPerSecond: 128000,
    });

    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) this.chunks.push(e.data);
    };

    this.mediaRecorder.start(1000);  // 1s Chunks (wie paply)
  }

  stop(): Blob {
    this.mediaRecorder?.stop();
    this.mediaRecorder?.stream.getTracks().forEach(t => t.stop());
    const blob = new Blob(this.chunks, { type: 'audio/webm' });
    this.chunks = [];
    return blob;
  }
}
```

**Transkription:**
- Audio Blob → Supabase Edge Function → Groq Whisper API
- Gleiche Konfiguration wie paply: `whisper-large-v3-turbo`, Sprache auto-detect
- Nur Code-Modus Polishing (technisch, präzise)

---

## 5. Crop Overlay

Wenn der User "Cropped Screenshot" wählt:

1. Background Script captured den sichtbaren Tab (`captureVisibleTab`)
2. Content Script zeigt ein Overlay über die gesamte Seite
3. User zieht ein Rechteck
4. Crop-Koordinaten werden an Background gesendet
5. Background cropped das Bild auf einem OffscreenDocument Canvas
6. Ergebnis geht zurück an Popup/SidePanel

```typescript
// Content Script: Crop Overlay
function showCropOverlay() {
  const overlay = document.createElement('div');
  overlay.id = 'paply-crop-overlay';
  overlay.style.cssText = `
    position: fixed; top: 0; left: 0; right: 0; bottom: 0;
    z-index: 2147483647; cursor: crosshair;
    background: rgba(0,0,0,0.3);
  `;

  let startX: number, startY: number;
  const selection = document.createElement('div');
  selection.style.cssText = `
    position: fixed; border: 2px solid #4f46e5;
    background: rgba(79,70,229,0.1);
  `;

  overlay.addEventListener('mousedown', (e) => {
    startX = e.clientX;
    startY = e.clientY;
    overlay.appendChild(selection);
  });

  overlay.addEventListener('mousemove', (e) => {
    if (!startX) return;
    const x = Math.min(startX, e.clientX);
    const y = Math.min(startY, e.clientY);
    const w = Math.abs(e.clientX - startX);
    const h = Math.abs(e.clientY - startY);
    selection.style.left = `${x}px`;
    selection.style.top = `${y}px`;
    selection.style.width = `${w}px`;
    selection.style.height = `${h}px`;
  });

  overlay.addEventListener('mouseup', (e) => {
    const rect = {
      x: Math.min(startX, e.clientX),
      y: Math.min(startY, e.clientY),
      width: Math.abs(e.clientX - startX),
      height: Math.abs(e.clientY - startY),
    };
    overlay.remove();
    chrome.runtime.sendMessage({ type: 'CROP_SELECTED', rect });
  });

  document.body.appendChild(overlay);
}
```

---

## 6. Build-Konfiguration (Vite)

```typescript
// browser-ext/vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'path';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    rollupOptions: {
      input: {
        popup: resolve(__dirname, 'src/popup/index.html'),
        sidepanel: resolve(__dirname, 'src/sidepanel/index.html'),
        'content-script': resolve(__dirname, 'src/content/content-script.ts'),
        'service-worker': resolve(__dirname, 'src/background/service-worker.ts'),
      },
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: 'chunks/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
});
```

---

## 7. Chrome Storage Schema

```typescript
// chrome.storage.local
interface ExtensionStorage {
  // Auth
  supabaseAccessToken: string;
  supabaseRefreshToken: string;
  userId: string;

  // Settings
  activeWorkspaceId: string;
  defaultProvider: 'github' | 'linear';
  defaultTarget: {
    github?: { owner: string; repo: string };
    linear?: { teamId: string; projectId: string };
  };

  // Rewind
  rewindDomains: string[];           // Max 3 Domains
  rewindEnabled: boolean;

  // Preferences
  language: 'de' | 'en';
  autoCapture: boolean;              // Console + Network auto-capture
}
```
