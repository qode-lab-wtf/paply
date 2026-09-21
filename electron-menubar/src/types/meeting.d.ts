// Datenmodell für den Meeting-Recorder (v2: Gemini-Audio-Auswertung, Audio 7 Tage, Bericht v2).
// Siehe docs/superpowers/specs/2026-09-21-meeting-gemini-audio-design.md

export type MeetingStatus = 'recording' | 'processing' | 'ready' | 'failed';
export type MeetingAnalysis = 'gemini' | 'groq-fallback' | null;

export interface MeetingIndexEntry {
  id: string; // `${startEpochMs}-${shortId}`
  startTime: string; // ISO
  durationMs: number;
  title: string; // Titel aus dem Bericht, sonst erster Satz; editierbar
  speakerCount: number;
  speakerNames?: string[]; // distinkte Sprecher-Labels (zeigt Namen in der Liste)
  preview: string; // erste ~120 Zeichen des Transkripts
  hasSummary: boolean;
  summaryError?: string | null; // 'rate_limit' | 'error', wenn Bericht-Erzeugung scheiterte
  favorite: boolean;
  // v2
  status?: MeetingStatus;
  analysis?: MeetingAnalysis;
  analysisError?: string | null; // Klartext, wenn die Auswertung scheiterte
  analysisAttempts?: number;
  progress?: string | null; // z. B. „Abschnitt 2 von 3“
  audioExpiresAt?: string | null; // ISO; danach werden die WAV-Dateien gelöscht
  audioDeleted?: boolean;
  captureStartGapMs?: { mic: number; system: number };
  systemRemote?: boolean; // System-Spur wurde als Gegenstelle gewertet (Anruf)
  callDetected?: boolean;
}

export interface MeetingSegment {
  tStart: number; // Sekunden ab Sessionstart
  tEnd: number;
  speaker: string; // 'Sprecher 1', 'Gegenstelle', umbenannt: freier Name
  channel: 'mic' | 'system';
  text: string; // wortgetreu
  unsicher?: boolean; // Zuordnung/Wortlaut laut Modell unklar
}

export interface MeetingTranscript {
  segments: MeetingSegment[];
  language: string;
  speakers?: { id: string; label: string; channel: 'mic' | 'system'; beschreibung: string }[];
}

export interface MeetingTodo {
  text: string;
  verantwortlich: string | null;
  frist?: string | null;
  erledigt: boolean;
}

export interface SummaryTopic { ueberschrift: string; inhalt: string }
export interface SummaryDecision { text: string; begruendung: string }

/** Bericht v2 (normalisiert). */
export interface SummaryV2 {
  schema: 2;
  titel: string;
  kurzfassung: string;
  themen: SummaryTopic[];
  entscheidungen: SummaryDecision[];
  offeneFragen: string[];
  todos: MeetingTodo[];
  generatedAt: string;
  model: string;
}

/** Gespeicherter Bericht: v2 oder alter v1 (kurzzusammenfassung/kernpunkte). */
export interface MeetingSummary {
  schema?: number;
  titel?: string;
  kurzfassung?: string;
  themen?: SummaryTopic[];
  entscheidungen?: SummaryDecision[];
  kurzzusammenfassung?: string;
  kernpunkte?: string[];
  todos: MeetingTodo[];
  offeneFragen: string[];
  generatedAt: string;
  model: string;
}

export interface MeetingFull {
  index: MeetingIndexEntry;
  transcript: MeetingTranscript;
  summary: MeetingSummary | null;
  audio: { mic: string | null; system: string | null }; // absolute Pfade (null, wenn gelöscht)
}
