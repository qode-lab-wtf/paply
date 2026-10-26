export interface NotesPreferences { enabled: boolean; captureHotkey: string; openHotkey: string; screenContext: boolean; imageUnderstanding: boolean; dailyTokens: number; dailyAudioMinutes: number; hasGroqKey: boolean; warning: string; platform: string; keyLabels?: Record<string, string> }
export type XY = { x: number; y: number };
export interface Note { id: string; kind: 'note'|'sticky'|'text'|'hub'|'table'|'image'|'point'; text: string; label: string; icon: string; position: XY|null; width: number; height: number|null; topicId: string|null; sourceId: string|null; sentenceIds: string[]; attachments: string[]; owner: 'user'|'ai'|'system'; rev: number; createdAt: number; pending?: boolean; structureId?: string; structureKind?: string; order?: number; groupId?: string; table?: { columns: string[]; rows: { label: string; cells: string[] }[] } }
export interface NoteEdge { id: string; source: string; target: string; sourceHandle: string; targetHandle: string; arrow: boolean; inferred: boolean; label: string; rev: number }
export interface NotesBoard { schemaVersion: number; rev: number; nodes: Record<string, Note>; edges: Record<string, NoteEdge>; topics: Record<string, { id: string; title: string; icon: string; owner: string; createdAt: number }>; viewport: { x: number; y: number; zoom: number }; entries: { id: string; kind: string; createdAt: number; state: string; message: string; durationMs: number }[]; assets: Record<string, { analysis?: { caption: string; visibleText: string } }>; preferences: NotesPreferences; capture: { active: boolean; paused: boolean; entryId: string|null; elapsedMs: number }; budget: { tokens: number; audioSeconds: number; requests: number }; canUndo: boolean; canRedo: boolean }
export interface CaptureState { phase: string; entryId: string|null; epoch: number; elapsedMs?: number; detail?: string; hasImage?: boolean }
export interface NotesSource { text?: string; command?: string|null; entry: { id: string; createdAt: number }; audioUrl: string|null }
export interface NotesAPI {
  editing(value: { id: string; active: boolean }): Promise<NotesBoard>;
  get(): Promise<NotesBoard>; command(ops: unknown[]): Promise<NotesBoard>; place(positions: { id: string; position: XY }[]): Promise<NotesBoard>; viewport(value: { x: number; y: number; zoom: number }): Promise<boolean>;
  undo(): Promise<NotesBoard>; redo(): Promise<NotesBoard>; addText(value: { text: string; position?: XY }): Promise<NotesBoard>;
  copy(text: string): Promise<boolean>; attach(value: { bytes: ArrayBuffer; target?: string|null; position?: XY }): Promise<NotesBoard>; camera(value: { target?: string|null; position?: XY }): Promise<NotesBoard>;
  source(id: string): Promise<NotesSource>; retry(id: string): Promise<NotesBoard>; discard(id: string): Promise<NotesBoard>; capture(): Promise<NotesBoard>; settings(): Promise<boolean>;
  onChange(cb: (value: NotesBoard) => void): () => void; onKey(cb: (value: string) => void): () => void;
}
declare global { interface Window {
  paplyNotes: NotesAPI;
  paplyNotesCapture: { ready(): Promise<CaptureState>; pcm(value: { entryId: string; epoch: number; seq: number; bytes: ArrayBuffer }): Promise<{ accepted: boolean; seq?: number }>; flushed(value: { entryId: string; epoch: number }): Promise<boolean>; failed(value: { entryId: string }): Promise<boolean>; stop(): Promise<boolean>; camera(): Promise<boolean>; onState(cb: (value: CaptureState) => void): () => void };
} }
