import { afterEach, describe, expect, it, vi } from 'vitest';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { captureMacApp, pasteMac } from '../dictation/mac-paste.js';
import { createWindowsFocus, pasteWindows } from '../dictation/windows-paste.js';
import { tick } from './helpers/dictation-main.js';
function child() { const proc = new EventEmitter(); proc.stdout = new PassThrough(); proc.stderr = new PassThrough(); proc.stdin = new PassThrough(); proc.kill = vi.fn(); return proc; }
afterEach(() => vi.useRealTimers());
describe('Mac: bestehender AppleScript-Einfügeweg', () => {
  it('merkt Ziel-App, verwendet dieselben Verzögerungen und wartet auf Exit', async () => {
    vi.useFakeTimers(); const capture = child(); const paste = child();
    const spawn = vi.fn().mockReturnValueOnce(capture).mockReturnValueOnce(paste);
    const name = captureMacApp({ spawnImpl: spawn }); capture.stdout.write('Editor\n'); capture.emit('close', 0);
    expect(await name).toBe('Editor');
    let finished = false;
    const result = pasteMac('Editor', { spawnImpl: spawn }).then(value => { finished = true; return value; });
    await vi.advanceTimersByTimeAsync(149); expect(spawn).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(spawn.mock.calls[1][0]).toBe('osascript');
    expect(spawn.mock.calls[1][1][1]).toContain('set frontmost of process "Editor" to true');
    expect(spawn.mock.calls[1][1][1]).toContain('delay 0.3');
    expect(spawn.mock.calls[1][1][1]).toContain('keystroke "v" using command down');
    expect(finished).toBe(false); paste.emit('close', 0); expect(await result).toBe(true);
  });
  it.each(['exit', 'stderr', 'spawn', 'timeout'])('meldet %s für Zwischenablage-Fallback', async failure => {
    vi.useFakeTimers(); const proc = child(); const spawn = vi.fn(() => proc);
    const result = pasteMac('Editor', { spawnImpl: spawn, timeoutMs: 100 });
    await vi.advanceTimersByTimeAsync(150);
    if (failure === 'exit') proc.emit('close', 1);
    if (failure === 'stderr') { proc.stderr.write('Not authorized to send Apple events (-1743)'); proc.emit('close', 0); }
    if (failure === 'spawn') proc.emit('error', Error('ENOENT'));
    if (failure === 'timeout') { await vi.advanceTimersByTimeAsync(100); expect(proc.kill).toHaveBeenCalledOnce(); }
    expect(await result).toBe(false);
  });
  it('behält den bisherigen Fokus-Fallback ohne Ziel-App', async () => {
    vi.useFakeTimers(); const proc = child(); const spawn = vi.fn(() => proc);
    const result = pasteMac(null, { spawnImpl: spawn }); await vi.advanceTimersByTimeAsync(150);
    expect(spawn.mock.calls[0][1][1]).toContain('delay 0.2'); proc.emit('close', 0); await result;
  });
});
describe('Windows-Fokushelfer und Ctrl+V', () => {
  it('startet einen Helfer für mehrere Befehle, korreliert und puffert Antworten', async () => {
    const proc = child(); const spawn = vi.fn(() => proc); const focus = createWindowsFocus({ spawnImpl: spawn });
    const capture = focus.capture(); proc.stdout.write('1 12'); proc.stdout.write('3\r\n'); expect(await capture).toBe('123');
    const restored = focus.restore('123'); proc.stdout.write('2 1\n'); expect(await restored).toBe(true);
    expect(spawn).toHaveBeenCalledOnce();
    expect(proc.stdin.read().toString()).toBe('1 get\n2 focus 123\n'); focus.stop();
  });
  it.each(['timeout', 'exit', 'error', 'stdin'])('fängt %s ab und startet bei Bedarf neu', async failure => {
    vi.useFakeTimers(); const proc = child(); const next = child(); const spawn = vi.fn().mockReturnValueOnce(proc).mockReturnValueOnce(next);
    const focus = createWindowsFocus({ spawnImpl: spawn, timeoutMs: 100 });
    const capture = focus.capture();
    if (failure === 'timeout') await vi.advanceTimersByTimeAsync(100);
    if (failure === 'exit') proc.emit('exit', 1);
    if (failure === 'error') proc.emit('error', Error('ENOENT'));
    if (failure === 'stdin') proc.stdin.emit('error', Error('EPIPE'));
    expect(await capture).toBeNull();
    const retry = focus.capture(); next.stdout.write('2 456\n'); expect(await retry).toBe('456');
    focus.stop(); expect(vi.getTimerCount()).toBe(0);
  });
  it('lehnt ungültige Fensterhandles ohne PowerShell-Ausführung ab', async () => {
    const spawn = vi.fn(); const focus = createWindowsFocus({ spawnImpl: spawn });
    expect(await focus.restore('1; bad-command')).toBe(false); expect(await focus.restore('0')).toBe(false);
    expect(spawn).not.toHaveBeenCalled();
  });
  it.each(['focus denied', 'no hook', 'key error', 'focus changed', 'success'])('%s lässt Text in Zwischenablage und meldet Dispatch', async mode => {
    const clipboard = { writeText: vi.fn() }; const hook = { keyTap: vi.fn(() => { if (mode === 'key error') throw Error('native'); }) };
    const focus = { restore: vi.fn(async () => mode !== 'focus denied'), capture: vi.fn(async () => mode === 'focus changed' ? '456' : '123') };
    const result = await pasteWindows({ text: 'Geheim', target: '123', clipboard, focus, hook: mode === 'no hook' ? null : hook });
    expect(clipboard.writeText).toHaveBeenCalledWith('Geheim'); expect(result).toBe(mode === 'success');
    if (mode === 'success') expect(hook.keyTap).toHaveBeenCalledWith(47, [29]);
    if (mode === 'focus denied' || mode === 'focus changed' || mode === 'no hook') expect(hook.keyTap).not.toHaveBeenCalled();
  });
});
