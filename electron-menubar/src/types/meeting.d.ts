// Datenmodell für den Meeting-Recorder (Phase 1).
// Siehe docs/superpowers/specs/2026-06-08-meeting-recorder-design.md

export interface MeetingIndexEntry {
  schemaVersion?: number;
  processingStatus?: string;
  processingError?: string | null;
  captureWarning?: string | null;
  audioExpiresAt?: number;
  reportNeedsRefresh?: boolean;
  id: string; // `${startEpochMs}-${shortId}`
  startTime: string; // ISO
  durationMs: number;
  title: string; // echtes Thema aus Protokoll, sonst erster Satz; editierbar
  speakerCount: number;
  speakerNames?: string[]; // distinkte Sprecher-Labels (zeigt Namen in der Liste)
  preview: string; // erste ~120 Zeichen des Transkripts
  hasSummary: boolean;
  summaryError?: string | null; // 'rate_limit' | 'error', wenn Protokoll-Erzeugung scheiterte
  favorite: boolean;
  // Sprecher-Trennung-Tracking (gesetzt beim Stop, nur bei Erfolg)
  diarizationUsed?: boolean;
  diarizationSeconds?: number;
  diarizationCostUsd?: number;
  diarizationSpeakers?: number;
}

export interface MeetingSegment {
  id?: string;
  speakerId?: string;
  uncertain?: boolean;
  possibleEchoOf?: string;
  corrected?: boolean;
  tStart: number; // Sekunden ab Sessionstart
  tEnd: number;
  speaker: 'me' | 'other' | string; // Phase 2: 'other-1', ...
  channel: 'mic' | 'system';
  text: string; // wortgetreu
}

export interface MeetingTranscript {
  provisional?: boolean;
  unmatchedCorrections?: string[];
  unmatchedSpeakerNames?: string[];
  segments: MeetingSegment[];
  language: string;
}

export interface MeetingTodo {
  text: string;
  verantwortlich: string | null;
  erledigt: boolean;
}

export interface MeetingSummary {
  reportStatus?: string;
  sections?: { title: string; claims?: { text: string; sources: { id: string; tStart: number; speaker: string; text: string }[] }[]; sources: { id: string; tStart: number; speaker: string; text: string }[] }[];
  kurzzusammenfassung: string;
  kernpunkte: string[];
  todos: MeetingTodo[];
  offeneFragen: string[];
  generatedAt: string;
  model: string;
}

export interface MeetingFull {
  audioOffsets?: { mic?: number; system?: number };
  index: MeetingIndexEntry;
  transcript: MeetingTranscript;
  summary: MeetingSummary | null;
  audio: { mic: string | null; system: string | null }; // absolute Pfade
}
