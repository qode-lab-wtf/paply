# paply.dev - Supabase Database Schema

## 1. ER-Diagramm (Konzept)

```
users ──< workspace_members >── workspaces
                                    │
                                    ├──< issues
                                    │      │
                                    │      ├──< issue_attachments
                                    │      └──< issue_captures
                                    │
                                    └──< integrations
```

---

## 2. Tabellen

### `workspaces`

Jedes Team/Projekt hat einen Workspace.

```sql
CREATE TABLE workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,          -- URL-freundlicher Name
  created_by UUID REFERENCES auth.users(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

### `workspace_members`

Verknüpfung User ↔ Workspace mit Rollen.

```sql
CREATE TYPE workspace_role AS ENUM ('owner', 'admin', 'member');

CREATE TABLE workspace_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role workspace_role DEFAULT 'member' NOT NULL,
  invited_at TIMESTAMPTZ DEFAULT now(),
  joined_at TIMESTAMPTZ,

  UNIQUE(workspace_id, user_id)
);
```

### `integrations`

GitHub/Linear Verbindungen pro Workspace.

```sql
CREATE TYPE integration_provider AS ENUM ('github', 'linear', 'jira');

CREATE TABLE integrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL,
  provider integration_provider NOT NULL,
  access_token TEXT NOT NULL,           -- Verschlüsselt gespeichert
  refresh_token TEXT,
  token_expires_at TIMESTAMPTZ,
  config JSONB DEFAULT '{}'::jsonb,     -- Provider-spezifische Config
  -- GitHub: { "owner": "...", "repos": ["..."] }
  -- Linear: { "teamId": "...", "teamName": "..." }
  connected_by UUID REFERENCES auth.users(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(workspace_id, provider)
);
```

### `issues`

Die erstellten Bug Reports.

```sql
CREATE TYPE issue_severity AS ENUM ('critical', 'major', 'minor', 'trivial');
CREATE TYPE issue_status AS ENUM ('draft', 'sent', 'synced');

CREATE TABLE issues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE NOT NULL,
  created_by UUID REFERENCES auth.users(id) NOT NULL,

  -- Issue Content
  title TEXT NOT NULL,
  description TEXT,
  steps_to_reproduce TEXT[],
  expected_behavior TEXT,
  actual_behavior TEXT,
  environment JSONB,                    -- { os, browser, viewport, url }
  severity issue_severity DEFAULT 'minor',
  labels TEXT[] DEFAULT '{}',

  -- Voice
  raw_transcription TEXT,               -- Original Transkription
  voice_duration_seconds INTEGER,

  -- Tracker-Info
  status issue_status DEFAULT 'draft',
  external_provider integration_provider,
  external_id TEXT,                     -- GitHub Issue #, Linear Issue ID
  external_url TEXT,                    -- Link zum externen Issue

  -- Meta
  page_url TEXT,                        -- URL wo Bug gefunden wurde
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

### `issue_attachments`

Screenshots, Recordings, annotierte Bilder.

```sql
CREATE TYPE attachment_type AS ENUM ('screenshot', 'screenshot_annotated', 'recording', 'rewind');

CREATE TABLE issue_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id UUID REFERENCES issues(id) ON DELETE CASCADE NOT NULL,
  type attachment_type NOT NULL,
  storage_path TEXT NOT NULL,           -- Pfad in Supabase Storage
  file_size INTEGER,
  mime_type TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### `issue_captures`

Auto-erfasste technische Daten.

```sql
CREATE TYPE capture_type AS ENUM ('console_logs', 'network_requests', 'system_info');

CREATE TABLE issue_captures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id UUID REFERENCES issues(id) ON DELETE CASCADE NOT NULL,
  type capture_type NOT NULL,
  data JSONB NOT NULL,                  -- Strukturierte Capture-Daten
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### `user_settings`

User-spezifische Einstellungen (pro User, nicht pro Workspace).

```sql
CREATE TABLE user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  default_workspace_id UUID REFERENCES workspaces(id),
  groq_api_key TEXT,                    -- Optional: eigener Groq Key
  language TEXT DEFAULT 'de',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 3. Supabase Storage Buckets

```sql
-- Screenshots und Recordings
INSERT INTO storage.buckets (id, name, public)
VALUES ('issue-attachments', 'issue-attachments', false);

-- Bucket Policy: Nur Workspace-Mitglieder können lesen/schreiben
CREATE POLICY "Workspace members can upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'issue-attachments'
    AND auth.uid() IN (
      SELECT user_id FROM workspace_members
      WHERE workspace_id = (storage.foldername(name))[1]::uuid
    )
  );

CREATE POLICY "Workspace members can view"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'issue-attachments'
    AND auth.uid() IN (
      SELECT user_id FROM workspace_members
      WHERE workspace_id = (storage.foldername(name))[1]::uuid
    )
  );
```

Storage-Pfad-Struktur:
```
issue-attachments/
  {workspace_id}/
    {issue_id}/
      screenshot.png
      screenshot_annotated.png
      recording.webm
```

---

## 4. Row Level Security (RLS) Policies

```sql
-- Workspaces: Nur Mitglieder sehen ihren Workspace
ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view workspace"
  ON workspaces FOR SELECT
  USING (
    id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Owner can update workspace"
  ON workspaces FOR UPDATE
  USING (
    id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid() AND role = 'owner')
  );

-- Issues: Nur Workspace-Mitglieder sehen Issues
ALTER TABLE issues ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view issues"
  ON issues FOR SELECT
  USING (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Members can create issues"
  ON issues FOR INSERT
  WITH CHECK (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Creator can update issue"
  ON issues FOR UPDATE
  USING (created_by = auth.uid());

-- Integrations: Nur Admins/Owner können Integrationen verwalten
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view integrations"
  ON integrations FOR SELECT
  USING (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins can manage integrations"
  ON integrations FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members
      WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
    )
  );

-- Workspace Members: Sehen wer im Team ist
ALTER TABLE workspace_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view other members"
  ON workspace_members FOR SELECT
  USING (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Admins can manage members"
  ON workspace_members FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members
      WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
    )
  );

-- Issue Attachments & Captures: Folgen dem Issue-Zugriff
ALTER TABLE issue_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE issue_captures ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view attachments"
  ON issue_attachments FOR SELECT
  USING (
    issue_id IN (
      SELECT id FROM issues WHERE workspace_id IN (
        SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Members can view captures"
  ON issue_captures FOR SELECT
  USING (
    issue_id IN (
      SELECT id FROM issues WHERE workspace_id IN (
        SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
      )
    )
  );
```

---

## 5. Indexes

```sql
-- Performance-relevante Indexes
CREATE INDEX idx_issues_workspace ON issues(workspace_id);
CREATE INDEX idx_issues_created_by ON issues(created_by);
CREATE INDEX idx_issues_created_at ON issues(created_at DESC);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_workspace_members_user ON workspace_members(user_id);
CREATE INDEX idx_workspace_members_workspace ON workspace_members(workspace_id);
CREATE INDEX idx_issue_attachments_issue ON issue_attachments(issue_id);
CREATE INDEX idx_issue_captures_issue ON issue_captures(issue_id);
CREATE INDEX idx_integrations_workspace ON integrations(workspace_id);
```

---

## 6. JSONB Strukturen

### `issue_captures.data` für `console_logs`
```json
[
  {
    "level": "error",
    "message": "TypeError: Cannot read property 'save' of undefined",
    "source": "app.js:142:15",
    "timestamp": 1708100000000,
    "stack": "TypeError: Cannot read property..."
  }
]
```

### `issue_captures.data` für `network_requests`
```json
[
  {
    "url": "https://api.example.com/save",
    "method": "POST",
    "status": 500,
    "duration_ms": 2340,
    "size_bytes": 1024,
    "type": "fetch",
    "timestamp": 1708100000000
  }
]
```

### `issue_captures.data` für `system_info`
```json
{
  "os": "macOS 14.3",
  "browser": "Chrome 121.0.6167.85",
  "viewport": { "width": 1920, "height": 1080 },
  "screen": { "width": 2560, "height": 1440 },
  "devicePixelRatio": 2,
  "language": "de-DE",
  "url": "https://app.example.com/editor",
  "userAgent": "Mozilla/5.0 ..."
}
```

### `integrations.config` für GitHub
```json
{
  "owner": "myorg",
  "repos": ["frontend", "backend", "docs"],
  "default_repo": "frontend",
  "default_labels": ["bug"]
}
```

### `integrations.config` für Linear
```json
{
  "team_id": "TEAM_123",
  "team_name": "Engineering",
  "default_project": "PROJECT_456",
  "default_label_ids": ["label_789"]
}
```
