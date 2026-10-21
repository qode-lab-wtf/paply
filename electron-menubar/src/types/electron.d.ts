import type { MeetingIndexEntry, MeetingFull, MeetingSummary } from './meeting';
import type { VoiceActivityMeta } from '../lib/voice-activity';

export interface Settings {
  groqApiKey: string;
  enablePolish: boolean;
  customVocabulary: string;
  polishUnavailable?: boolean;
  shortcut: string;
  autoStart: boolean;
  language: 'de' | 'en';
  autopaste: boolean;
  beepEnabled: boolean;
  copyToClipboard: boolean;
  hideDock: boolean;
  activeProfile: string;
  pttThreshold: number;
  meetingHotkey: string;
  meetingEnabled: boolean;
  onboardingCompleted: boolean;
  // System-Audio (Gegenstelle eines Anrufs auf diesem Computer): 'auto' = automatisch erkennen
  // (empfohlen), 'always' = immer einbeziehen, 'never' = nie. Default 'auto'.
  systemAudioMode: 'auto' | 'always' | 'never';
  // Gemini: Meeting-Auswertung (Audio → Sprecher/Wortlaut) + Bericht. 'auto' = Gemini, bei Limit Groq.
  geminiApiKey: string;
  llmProvider: 'auto' | 'groq' | 'gemini';
}

export interface HistoryItem {
  id: number;
  timestamp: string;
  transcript: string;
  polished: string | null;
  language: string;
  role: string;
  wordCount: number;
  delta: {
    wordsBefore: number;
    wordsAfter: number;
    wordsDiff: number;
    fillersRemoved: number;
    fillersList: string[];
  } | null;
  polishUsed: boolean;
  favorite: boolean;
}

export interface Stats {
  wordsTotal: number;
  wordsToday: number;
  wordsWeek: number;
  minutesTotal: number;
  minutesToday: number;
  minutesWeek: number;
  sessionsCount: number;
  sessionsToday: number;
  sessionsWeek: number;
  errorsCount: number;
}

export interface Profile {
  name: string;
  language: string;
  polishFlavor: string;
  autopaste: boolean;
  hotkey?: string;
}

export interface CustomAgent {
  id: string;
  name: string;
  icon?: string;
  color?: string;
  tone?: string;
  format?: string;
  length?: string;
  creativity?: number;
  outputLang?: string;
  domain?: string;
  fillerWords?: boolean;
  isPromptGenerator?: boolean;
  hotkey?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface Snippet {
  id: string;
  name: string;
  template: string;
}

export interface ScreenContext {
  files: string[];
  activeFile?: string;
  visibleCode?: string;
  errors?: string[];
  context?: string;
}

export interface Platform {
  isMac: boolean;
  isWin: boolean;
  platform: string;
  version?: string;
}

export interface MicrophonePermission {
  status: string;
  accessibilityRequired: boolean;
  accessibilityGranted: boolean;
}

export interface ElectronAPI {
  onSettingsChanged: (cb: () => void) => () => void;
  validateGroqKey: (key: string, saveAnyway?: boolean) => Promise<{ status: 'valid' | 'invalid' | 'unavailable'; saved: boolean }>;
  completeOnboarding: () => Promise<boolean>;
  openOnboarding: () => Promise<boolean>;
  openGroqKeys: () => Promise<void>;
  microphonePermission: (request?: boolean) => Promise<MicrophonePermission>;
  openMicrophoneSettings: () => Promise<void>;

  // Settings
  getSettings: () => Promise<Settings>;
  setSettings: (settings: Partial<Settings>) => Promise<true | { success: false; error: { code: 'HOTKEY_REGISTRATION_FAILED'; field: 'shortcut'; message: string } }>;

  // History
  getHistory: () => Promise<HistoryItem[]>;
  clearHistory: () => Promise<boolean>;
  copyHistoryItem: (id: number) => Promise<boolean>;
  deleteHistoryItem: (id: number) => Promise<boolean>;
  toggleFavorite: (id: number) => Promise<boolean>;
  onHistoryUpdated: (cb: (history: HistoryItem[]) => void) => void;

  // Recording
  onRecordingStart: (cb: (data: { jobId: string }) => void) => () => void;
  onRecordingStop: (cb: (data: { jobId: string }) => void) => () => void;
  recordingStarted: (jobId: string) => void;
  recordingFailed: (jobId: string, message: string) => void;
  onRecordingState: (cb: (data: { isRecording: boolean }) => void) => () => void;
  onStatusUpdate: (cb: (status: { status: 'transcribing' | 'polishing' | 'done' | 'empty' | 'error' | 'leaving'; detail?: string; jobId?: string }) => void) => () => void;
  onErrorRetry: (cb: (data: { message: string; hotkey: string; jobId?: string }) => void) => () => void;
  sendAudio: (audioData: ArrayBuffer, voiceActivity?: VoiceActivityMeta, jobId?: string) => void;

  // Transcription control
  startTranscription: () => Promise<boolean>;
  stopTranscription: () => Promise<boolean>;
  getTranscriptionStatus: () => Promise<{ isRecording: boolean }>;

  // Stats
  getStats: () => Promise<Stats>;
  getOwnerStats: () => Promise<{ tokensGroq: number; tokensGroqPolish: number; estimatedCost: number } | null>;
  onStatsUpdated: (cb: (stats: Stats) => void) => void;

  // Owner Mode
  checkOwnerMode: () => Promise<boolean>;
  toggleOwnerMode: (password: string) => Promise<boolean>;

  // Profiles / Agents
  getProfiles: () => Promise<{ active: string; profiles: Record<string, Profile>; customAgents: CustomAgent[] }>;
  setActiveProfile: (profileId: string) => Promise<boolean>;
  updateProfile: (profileId: string, updates: Partial<Profile>) => Promise<boolean>;
  onAgentSwitched: (cb: (data: { id: string; name: string; icon?: string; color?: string }) => void) => () => void;

  // Custom Agents CRUD
  getCustomAgents: () => Promise<CustomAgent[]>;
  createAgent: (agent: Partial<CustomAgent>) => Promise<CustomAgent>;
  updateAgent: (agentId: string, updates: Partial<CustomAgent>) => Promise<CustomAgent | null>;
  deleteAgent: (agentId: string) => Promise<boolean>;
  reorderAgents: (orderedIds: string[]) => Promise<CustomAgent[]>;
  updateAgentHotkey: (agentId: string, hotkey: string) => Promise<CustomAgent | null>;

  // Screen Parser
  captureScreen: () => Promise<ScreenContext | null>;
  getScreenContext: () => Promise<ScreenContext | null>;
  onScreenContext: (cb: (data: ScreenContext) => void) => void;

  // Snippets
  getSnippets: () => Promise<Snippet[]>;
  addSnippet: (snippet: { name: string; template: string }) => Promise<Snippet>;
  deleteSnippet: (id: string) => Promise<boolean>;
  applySnippet: (snippetId: string, text: string) => Promise<string>;

  // Accessibility
  openAccessibilitySettings: () => void;

  // Meeting-Recorder
  startMeeting: () => Promise<{ id: string } | null>;
  stopMeeting: () => Promise<{ id: string | null } | null>;
  getMeetingStatus: () => Promise<{ active: boolean; id: string | null; callActive: boolean; micReady?: boolean }>;
  sendMicCaptureStarted: (d: { firstSampleAtMs: number }) => void;
  sendMicPcm: (buf: ArrayBuffer) => void;
  sendMicLevel: (lvl: number) => void;
  sendSystemPcm: (buf: ArrayBuffer) => void;
  captureFlushed: () => Promise<boolean>;
  listMeetings: () => Promise<MeetingIndexEntry[]>;
  getMeeting: (id: string) => Promise<MeetingFull | null>;
  deleteMeeting: (id: string) => Promise<boolean>;
  reanalyzeMeeting: (id: string) => Promise<{ ok?: boolean; error?: string }>;
  regenerateSummary: (id: string) => Promise<MeetingSummary | { error: string } | null>;
  renameSpeaker: (id: string, fromSpeaker: string, toName: string) => Promise<boolean>;
  toggleMeetingTodo: (id: string, idx: number) => Promise<boolean>;
  exportMeeting: (payload: { title: string; markdown: string }) => Promise<boolean>;
  onMeetingStatus: (cb: (s: { color: 'green' | 'yellow' | 'red'; reason: string; durationMs: number; micLevel: number; systemLevel: number; micReady?: boolean }) => void) => () => void;
  onMeetingStarted: (cb: (d: { id: string; callActive?: boolean }) => void) => () => void;
  onMeetingStopped: (cb: (d: { id: string }) => void) => () => void;
  onMeetingCallState: (cb: (d: { active: boolean }) => void) => () => void;
  onMeetingCaptureStop: (cb: (d: { id: string }) => void) => () => void;
  onMeetingsUpdated: (cb: (d: { id: string; status: string; progress?: string }) => void) => () => void;

  // Platform
  getPlatform: () => Promise<Platform>;
}

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}
