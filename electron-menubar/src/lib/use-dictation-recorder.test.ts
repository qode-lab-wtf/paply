import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useDictationRecorder } from '../apps/recording/useDictationRecorder';

const react = vi.hoisted(() => ({ effects: [] as Array<() => (() => void)>, states: [] as unknown[] }));
vi.mock('react', () => ({
  useEffect: (fn: () => (() => void)) => react.effects.push(fn),
  useRef: (value: unknown) => ({ current: value }),
  useCallback: (fn: unknown) => fn,
  useState: (initial: unknown) => [initial, (value: unknown) => react.states.push(value)],
}));
const activity = vi.hoisted(() => ({ start: vi.fn() }));
vi.mock('@/lib/voice-activity-recorder', () => ({ startVoiceActivityMeasurement: activity.start }));
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; }
const tick = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };
function stream() { const stop = vi.fn(); return { stream: { getTracks: () => [{ stop }] } as unknown as MediaStream, stop }; }

class FakeAudioContext {
  currentTime = 0; destination = {}; close = vi.fn(async () => {});
  createAnalyser() { return { fftSize: 32, frequencyBinCount: 16, getByteFrequencyData: vi.fn() }; }
  createMediaStreamSource() { return { connect: vi.fn() }; }
}
class FakeRecorder {
  static isTypeSupported() { return true; }
  static all: FakeRecorder[] = [];
  state = 'inactive'; mimeType = 'audio/webm';
  ondataavailable?: (event: { data: Blob }) => void;
  onstop?: () => Promise<void>; onerror?: () => void;
  constructor(public stream: MediaStream) { FakeRecorder.all.push(this); }
  start() { this.state = 'recording'; }
  stop() { this.state = 'inactive'; this.ondataavailable?.({ data: new Blob(['session-' + FakeRecorder.all.indexOf(this)]) }); void this.onstop?.(); }
}
let cleanup: (() => void) | undefined;
beforeEach(() => {
  react.effects = []; react.states = []; FakeRecorder.all = [];
  activity.start.mockReset().mockImplementation(() => vi.fn(() => ({ durationMs: 1000, speechMs: 800 })));
  vi.stubGlobal('AudioContext', FakeAudioContext); vi.stubGlobal('MediaRecorder', FakeRecorder);
  vi.stubGlobal('requestAnimationFrame', vi.fn(() => 1)); vi.stubGlobal('cancelAnimationFrame', vi.fn());
});
afterEach(() => { cleanup?.(); cleanup = undefined; vi.unstubAllGlobals(); });
function setup(platform: 'mac' | 'win') {
  const handlers: Record<string, (data: any) => any> = {};
  const listen = (name: string) => (fn: (data: any) => any) => { handlers[name] = fn; return vi.fn(() => { delete handlers[name]; }); };
  const getUserMedia = vi.fn();
  const api = {
    getPlatform: vi.fn(async () => ({ isMac: platform === 'mac', isWin: platform === 'win' })),
    getSettings: vi.fn(async () => ({ beepEnabled: false })),
    onRecordingStart: listen('start'), onRecordingStop: listen('stop'), onStatusUpdate: listen('status'),
    onErrorRetry: listen('retry'), onAgentSwitched: listen('agent'),
    recordingStarted: vi.fn(), recordingFailed: vi.fn(), sendAudio: vi.fn(),
  };
  vi.stubGlobal('window', { electronAPI: api }); vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } });
  useDictationRecorder(); cleanup = react.effects[0]();
  return { api, handlers, getUserMedia };
}
for (const platform of ['mac', 'win'] as const) describe(`Echter Recorder-Hook ${platform}`, () => {
  it('Stop während settings verhindert den Mikrofonstart', async () => {
    const { api, handlers, getUserMedia } = setup(platform);
    const settings = deferred<{ beepEnabled: boolean }>(); api.getSettings.mockReturnValueOnce(settings.promise);
    const start = handlers.start({ jobId: 'one' }); handlers.stop({ jobId: 'one' });
    settings.resolve({ beepEnabled: false }); await start;
    expect(getUserMedia).not.toHaveBeenCalled(); expect(api.recordingStarted).not.toHaveBeenCalled();
  });
  it('Stop während getUserMedia stoppt den verspäteten Stream sofort', async () => {
    const { api, handlers, getUserMedia } = setup(platform);
    const mic = deferred<MediaStream>(); getUserMedia.mockReturnValueOnce(mic.promise);
    const start = handlers.start({ jobId: 'one' }); await tick(); handlers.stop({ jobId: 'one' });
    const late = stream(); mic.resolve(late.stream); await start;
    expect(late.stop).toHaveBeenCalledOnce(); expect(api.recordingStarted).not.toHaveBeenCalled();
    expect(FakeRecorder.all).toHaveLength(0);
  });
  it('verweigerter Mikrofonzugriff wird mit Plattformhinweis und ID an Main gemeldet', async () => {
    const { api, handlers, getUserMedia } = setup(platform);
    getUserMedia.mockRejectedValueOnce(Object.assign(new Error('denied'), { name: 'NotAllowedError' }));
    await handlers.start({ jobId: 'one' });
    expect(api.recordingFailed).toHaveBeenCalledWith('one', expect.stringContaining(platform === 'mac' ? 'Systemeinstellungen' : 'Windows-Einstellungen'));
    expect(react.states).toContain('error');
    getUserMedia.mockResolvedValueOnce(stream().stream); await handlers.start({ jobId: 'two' });
    expect(api.recordingStarted).toHaveBeenCalledWith('two');
  });
  it('später alter Stream stoppt keine neue Aufnahme', async () => {
    const { api, handlers, getUserMedia } = setup(platform);
    const mic = deferred<MediaStream>(); getUserMedia.mockReturnValueOnce(mic.promise);
    const old = handlers.start({ jobId: 'one' }); await tick(); handlers.stop({ jobId: 'one' });
    const next = stream(); getUserMedia.mockResolvedValueOnce(next.stream); await handlers.start({ jobId: 'two' });
    const late = stream(); mic.resolve(late.stream); await old;
    expect(late.stop).toHaveBeenCalledOnce(); expect(next.stop).not.toHaveBeenCalled();
    expect(api.recordingStarted.mock.calls).toEqual([['two']]);
  });
  it('sendet Chunks und Metadaten der alten Session trotz neuem Aufnahmestart mit alter ID', async () => {
    const { api, handlers, getUserMedia } = setup(platform);
    const first = stream(); getUserMedia.mockResolvedValueOnce(first.stream); await handlers.start({ jobId: 'one' });
    handlers.stop({ jobId: 'one' });
    const second = stream(); getUserMedia.mockResolvedValueOnce(second.stream); await handlers.start({ jobId: 'two' });
    for (let i = 0; !api.sendAudio.mock.calls.length && i < 50; i++) await new Promise(resolve => setTimeout(resolve, 1));
    expect(api.sendAudio).toHaveBeenCalledWith(expect.any(ArrayBuffer), expect.objectContaining({ speechMs: 800 }), 'one');
    const sent = api.sendAudio.mock.calls[0][0]; expect(new TextDecoder().decode(sent)).toBe('session-0');
    expect(first.stop).toHaveBeenCalledOnce(); expect(second.stop).not.toHaveBeenCalled();
  });
  it('Unmount räumt IPC-Listener auf und stoppt den noch ausstehenden Stream', async () => {
    const { handlers, getUserMedia } = setup(platform);
    const mic = deferred<MediaStream>(); getUserMedia.mockReturnValueOnce(mic.promise);
    const start = handlers.start({ jobId: 'one' }); await tick(); cleanup?.(); cleanup = undefined;
    const late = stream(); mic.resolve(late.stream); await start;
    expect(late.stop).toHaveBeenCalledOnce(); expect(Object.keys(handlers)).toHaveLength(0);
  });
  it('MediaRecorder-Fehler schließt Tracks und meldet Fehler mit ID', async () => {
    const { api, handlers, getUserMedia } = setup(platform);
    const mic = stream(); getUserMedia.mockResolvedValueOnce(mic.stream); await handlers.start({ jobId: 'one' });
    FakeRecorder.all[0].onerror?.();
    expect(mic.stop).toHaveBeenCalledOnce(); expect(api.recordingFailed).toHaveBeenCalledWith('one', expect.any(String));
    expect(api.sendAudio).not.toHaveBeenCalled();
  });
});
