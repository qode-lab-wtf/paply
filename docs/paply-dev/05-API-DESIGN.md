# paply.dev - API Design

## 1. Übersicht

Alle API-Calls laufen über **Supabase Edge Functions** (Deno) oder **Next.js API Routes** im Dashboard.

Die Extension kommuniziert mit Supabase direkt (Auth, DB, Storage) und über Edge Functions (Groq API, Issue Tracker APIs).

---

## 2. Supabase Edge Functions

### `POST /functions/v1/transcribe`

Transkribiert Audio via Groq Whisper.

**Request:**
```typescript
// multipart/form-data
{
  file: Blob;                   // Audio WebM/Opus
  language?: 'de' | 'en';      // Optional, sonst auto-detect
}
```

**Response:**
```json
{
  "text": "Der Save-Button funktioniert nicht, wenn ich draufklicke passiert gar nichts",
  "language": "de",
  "duration_seconds": 8.5
}
```

**Implementierung:**
```typescript
// supabase/functions/transcribe/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

serve(async (req) => {
  const formData = await req.formData();
  const file = formData.get('file') as File;

  const groqForm = new FormData();
  groqForm.append('file', file, 'audio.webm');
  groqForm.append('model', 'whisper-large-v3-turbo');

  const response = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('GROQ_API_KEY')}`,
    },
    body: groqForm,
  });

  const result = await response.json();
  return new Response(JSON.stringify({
    text: result.text,
    language: result.language,
    duration_seconds: result.duration,
  }));
});
```

---

### `POST /functions/v1/structure-issue`

Strukturiert Voice + Kontext zu einem Issue.

**Request:**
```typescript
interface StructureIssueRequest {
  transcription: string;
  context: {
    screenshot_url?: string;          // Supabase Storage URL
    console_logs?: ConsoleEntry[];
    network_requests?: NetworkEntry[];
    system_info?: SystemInfo;
    page_url?: string;
  };
  language?: 'de' | 'en';
}
```

**Response:**
```typescript
interface StructureIssueResponse {
  title: string;
  description: string;
  steps_to_reproduce: string[];
  expected_behavior: string;
  actual_behavior: string;
  environment: string;
  severity: 'critical' | 'major' | 'minor' | 'trivial';
  labels: string[];
}
```

**AI Prompt (Groq Llama 3.3 70B):**
```
Du bist ein technischer Issue-Strukturierer. Der User hat einen Bug per Sprache beschrieben.
Erstelle ein strukturiertes Bug-Report Issue aus der Transkription und dem technischen Kontext.

## Regeln:
- Title: Kurz, prägnant, max 80 Zeichen
- Description: 2-3 Sätze, was passiert
- Steps to Reproduce: Nummerierte Liste der Schritte
- Expected Behavior: Was hätte passieren sollen
- Actual Behavior: Was tatsächlich passiert (inkl. relevanter Errors)
- Severity: Basierend auf Impact (critical/major/minor/trivial)
- Labels: 2-4 passende Tags

## Kontext:
- Console Errors und Network Requests sind automatisch erfasst
- Beziehe dich auf konkrete Errors aus den Console Logs falls vorhanden
- Nenne fehlgeschlagene Network Requests falls relevant
- Die Environment-Info wird automatisch angehängt

## Transkription:
{transcription}

## Console Logs:
{console_logs}

## Network Requests:
{network_requests}

## System Info:
{system_info}

## Seiten-URL:
{page_url}

Antworte im JSON-Format.
```

---

### `POST /functions/v1/create-github-issue`

Erstellt ein GitHub Issue.

**Request:**
```typescript
interface CreateGitHubIssueRequest {
  issue: StructuredIssue;
  owner: string;
  repo: string;
  screenshot_url?: string;
  console_logs?: ConsoleEntry[];
  network_requests?: NetworkEntry[];
}
```

**Response:**
```json
{
  "id": 42,
  "url": "https://github.com/myorg/frontend/issues/42",
  "number": 42
}
```

**Implementierung:**
```typescript
// GitHub Issue Body wird als Markdown generiert:
function buildGitHubIssueBody(issue: StructuredIssue, extras: IssueExtras): string {
  let body = `## Description\n${issue.description}\n\n`;

  body += `## Steps to Reproduce\n`;
  issue.steps_to_reproduce.forEach((step, i) => {
    body += `${i + 1}. ${step}\n`;
  });

  body += `\n## Expected Behavior\n${issue.expected_behavior}\n\n`;
  body += `## Actual Behavior\n${issue.actual_behavior}\n\n`;

  if (extras.screenshot_url) {
    body += `## Screenshot\n![Bug Screenshot](${extras.screenshot_url})\n\n`;
  }

  if (extras.console_logs?.length) {
    body += `## Console Logs\n\`\`\`\n`;
    extras.console_logs.forEach(log => {
      body += `[${log.level.toUpperCase()}] ${log.message}\n`;
      if (log.source) body += `  at ${log.source}\n`;
    });
    body += `\`\`\`\n\n`;
  }

  if (extras.network_requests?.length) {
    body += `## Failed Network Requests\n`;
    extras.network_requests
      .filter(r => r.status >= 400 || r.status === 0)
      .forEach(r => {
        body += `- \`${r.method} ${r.url}\` → ${r.status} (${r.duration_ms}ms)\n`;
      });
    body += `\n`;
  }

  body += `## Environment\n${issue.environment}\n\n`;
  body += `---\n*Created with [paply.dev](https://paply.dev)*`;

  return body;
}
```

**GitHub API Call:**
```typescript
const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/issues`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${accessToken}`,
    'Accept': 'application/vnd.github.v3+json',
  },
  body: JSON.stringify({
    title: issue.title,
    body: buildGitHubIssueBody(issue, extras),
    labels: issue.labels,
  }),
});
```

---

### `POST /functions/v1/create-linear-issue`

Erstellt ein Linear Issue.

**Request:**
```typescript
interface CreateLinearIssueRequest {
  issue: StructuredIssue;
  team_id: string;
  project_id?: string;
  screenshot_url?: string;
  console_logs?: ConsoleEntry[];
  network_requests?: NetworkEntry[];
}
```

**Response:**
```json
{
  "id": "LIN-123",
  "url": "https://linear.app/myorg/issue/LIN-123",
  "identifier": "LIN-123"
}
```

**Linear GraphQL:**
```graphql
mutation CreateIssue($input: IssueCreateInput!) {
  issueCreate(input: $input) {
    success
    issue {
      id
      identifier
      url
    }
  }
}
```

```typescript
// Linear nutzt Markdown - gleiche Body-Funktion wie GitHub
const response = await fetch('https://api.linear.app/graphql', {
  method: 'POST',
  headers: {
    'Authorization': apiKey,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    query: CREATE_ISSUE_MUTATION,
    variables: {
      input: {
        title: issue.title,
        description: buildLinearIssueBody(issue, extras),
        teamId: team_id,
        projectId: project_id,
        priority: severityToLinearPriority(issue.severity),
        labelIds: [],  // TODO: Map labels
      },
    },
  }),
});
```

**Severity → Linear Priority Mapping:**
```typescript
function severityToLinearPriority(severity: string): number {
  switch (severity) {
    case 'critical': return 1;  // Urgent
    case 'major': return 2;     // High
    case 'minor': return 3;     // Medium
    case 'trivial': return 4;   // Low
    default: return 3;
  }
}
```

---

## 3. Auth Flows

### GitHub OAuth

```
1. Extension öffnet: https://github.com/login/oauth/authorize
   ?client_id={GITHUB_CLIENT_ID}
   &redirect_uri=https://paply.dev/api/auth/github/callback
   &scope=repo
   &state={random_state}

2. User autorisiert auf GitHub

3. GitHub redirected zu: https://paply.dev/api/auth/github/callback?code={code}

4. Dashboard Backend tauscht code gegen access_token:
   POST https://github.com/login/oauth/access_token
   { client_id, client_secret, code }

5. access_token wird in Supabase DB gespeichert (integrations Tabelle)

6. Extension wird benachrichtigt (via Supabase Realtime oder Polling)
```

### Linear OAuth

```
1. Extension öffnet: https://linear.app/oauth/authorize
   ?client_id={LINEAR_CLIENT_ID}
   &redirect_uri=https://paply.dev/api/auth/linear/callback
   &response_type=code
   &scope=write

2. User autorisiert auf Linear

3. Linear redirected zu Callback

4. Backend tauscht code gegen access_token:
   POST https://api.linear.app/oauth/token
   { code, redirect_uri, client_id, client_secret, grant_type: 'authorization_code' }

5. access_token wird gespeichert
```

---

## 4. Supabase Client in Extension

```typescript
// shared/supabase-client.ts
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://your-project.supabase.co';
const supabaseAnonKey = 'your-anon-key';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: {
      // Chrome Extension Storage statt localStorage
      getItem: (key) => new Promise((resolve) => {
        chrome.storage.local.get(key, (result) => resolve(result[key] || null));
      }),
      setItem: (key, value) => new Promise((resolve) => {
        chrome.storage.local.set({ [key]: value }, resolve);
      }),
      removeItem: (key) => new Promise((resolve) => {
        chrome.storage.local.remove(key, resolve);
      }),
    },
  },
});
```

---

## 5. Screenshot Upload

```typescript
// Screenshot als Base64 → Supabase Storage
async function uploadScreenshot(
  workspaceId: string,
  issueId: string,
  dataUrl: string,
  filename: string = 'screenshot.png'
): Promise<string> {
  // Base64 → Blob
  const response = await fetch(dataUrl);
  const blob = await response.blob();

  const path = `${workspaceId}/${issueId}/${filename}`;

  const { data, error } = await supabase.storage
    .from('issue-attachments')
    .upload(path, blob, {
      contentType: 'image/png',
      upsert: true,
    });

  if (error) throw error;

  // Public URL generieren
  const { data: urlData } = supabase.storage
    .from('issue-attachments')
    .getPublicUrl(path);

  return urlData.publicUrl;
}
```

---

## 6. Kompletter Issue-Erstellungs-Flow (API-Sicht)

```
Extension                    Supabase                      External
────────                    ─────────                     ─────────

1. Audio Blob ──────────────> Edge: /transcribe
                              │ → Groq Whisper API
                              │ ← Transcription
   Transcription <────────────┘

2. Screenshot ──────────────> Storage: upload
   Storage URL <──────────────┘

3. {transcription,           > Edge: /structure-issue
    screenshot_url,           │ → Groq Llama 3.3
    consoleLogs,              │ ← Structured Issue
    networkRequests,          │
    systemInfo}               │
   Structured Issue <─────────┘

4. User reviewed & edited (lokal in Extension)

5. Structured Issue ────────> Edge: /create-github-issue
                              │ → GitHub API
                              │   POST /repos/.../issues
   Issue URL <────────────────┘      ← Issue created

6. {issue, attachments,     > DB: INSERT INTO issues
    captures}                > DB: INSERT INTO issue_attachments
                             > DB: INSERT INTO issue_captures
   Saved <────────────────────┘
```
