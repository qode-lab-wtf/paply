import { afterEach, describe, expect, it, vi } from 'vitest';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { captureMacApp, pasteMac } from '../dictation/mac-paste.js';
import { createWindowsFocus, pasteWindows } from '../dictation/windows-paste.js';
function child() { const proc = new EventEmitter(); proc.stdout = new PassThrough(); proc.stderr = new PassThrough(); proc.stdin = new PassThrough(); proc.kill = vi.fn(); return proc; }
const fixtures = [];
function focus(options = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-focus-test-'));
  const helper = createWindowsFocus({ scriptDirectory: () => directory, ...options });
  fixtures.push({ helper, directory }); return helper;
}
afterEach(() => {
  for (const { helper, directory } of fixtures.splice(0)) { helper.stop(); fs.rmSync(directory, { recursive: true, force: true }); }
  vi.useRealTimers();
});
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
  it.each(['exit', 'spawn', 'timeout'])('meldet %s für Zwischenablage-Fallback', async failure => {
    vi.useFakeTimers(); const proc = child(); const spawn = vi.fn(() => proc);
    const result = pasteMac('Editor', { spawnImpl: spawn, timeoutMs: 100 });
    await vi.advanceTimersByTimeAsync(150);
    if (failure === 'exit') proc.emit('close', 1);
    if (failure === 'spawn') proc.emit('error', Error('ENOENT'));
    if (failure === 'timeout') { await vi.advanceTimersByTimeAsync(100); expect(proc.kill).toHaveBeenCalledOnce(); }
    expect(await result).toBe(false);
  });
  it('bewertet stderr-Warnungen bei Exitcode 0 als Erfolg', async () => {
    vi.useFakeTimers(); const proc = child();
    const result = pasteMac('Editor', { spawnImpl: () => proc }); await vi.advanceTimersByTimeAsync(150);
    proc.stderr.write('An AppleScript warning'); proc.emit('close', 0); expect(await result).toBe(true);
  });
  it('lässt einem erstmals offenen Automationsdialog bis zu 15 s Zeit', async () => {
    vi.useFakeTimers(); const proc = child();
    const result = pasteMac('Editor', { spawnImpl: () => proc });
    await vi.advanceTimersByTimeAsync(150 + 10000); expect(proc.kill).not.toHaveBeenCalled();
    proc.emit('close', 0); expect(await result).toBe(true); expect(vi.getTimerCount()).toBe(0);
  });
  it('behält den bisherigen Fokus-Fallback ohne Ziel-App', async () => {
    vi.useFakeTimers(); const proc = child(); const spawn = vi.fn(() => proc);
    const result = pasteMac(null, { spawnImpl: spawn }); await vi.advanceTimersByTimeAsync(150);
    expect(spawn.mock.calls[0][1][1]).toContain('delay 0.2'); proc.emit('close', 0); await result;
  });
});
describe('Windows-Fokushelfer und Ctrl+V', () => {
  it('wärmt einen Helfer vor, startet eine lesbare ps1-Datei und korreliert gepufferte Antworten', async () => {
    const proc = child(); const spawn = vi.fn(() => proc); const helper = focus({ spawnImpl: spawn });
    helper.start(); const capture = helper.capture(); proc.stdout.write('1 12'); proc.stdout.write('3\r\n'); expect(await capture).toBe('123');
    const restored = helper.restore('123'); proc.stdout.write('2 1\n'); expect(await restored).toBe(true);
    expect(spawn).toHaveBeenCalledOnce();
    expect(proc.stdin.read().toString()).toBe('1 get\n2 focus 123\n');
    const args = spawn.mock.calls[0][1];
    expect(args).not.toContain('-EncodedCommand'); expect(args).toContain('-File');
    const scriptPath = args[args.indexOf('-File') + 1];
    expect(fs.readFileSync(scriptPath, 'utf8')).toContain('SetForegroundWindow');
    expect(fs.readFileSync(scriptPath, 'utf8')).toContain('[Console]::ReadLine()');
  });
  it('erste Anfrage nach Start darf 6 s benötigen, spätere Anfragen höchstens 2 s', async () => {
    vi.useFakeTimers(); const proc = child(); const spawn = vi.fn(() => proc); const helper = focus({ spawnImpl: spawn });
    helper.start(); let finished = false; const cold = helper.capture().then(value => { finished = true; return value; });
    await vi.advanceTimersByTimeAsync(5999); expect(finished).toBe(false);
    proc.stdout.write('1 123\n'); expect(await cold).toBe('123');
    const warm = helper.capture(); await vi.advanceTimersByTimeAsync(2000); expect(await warm).toBeNull();
    expect(proc.kill).not.toHaveBeenCalled(); expect(spawn).toHaveBeenCalledOnce();
  });
  it('Timeout betrifft nur eine Anfrage, ignoriert ihre späte Antwort und lässt den Helfer laufen', async () => {
    vi.useFakeTimers(); const proc = child(); const spawn = vi.fn(() => proc);
    const helper = focus({ spawnImpl: spawn, coldTimeoutMs: 100, timeoutMs: 200 });
    const first = helper.capture(); await vi.advanceTimersByTimeAsync(50);
    const second = helper.capture(); await vi.advanceTimersByTimeAsync(50);
    expect(await first).toBeNull(); expect(proc.kill).not.toHaveBeenCalled();
    proc.stdout.write('1 111\n2 222\n'); expect(await second).toBe('222');
    const third = helper.capture(); proc.stdout.write('3 333\n'); expect(await third).toBe('333');
    expect(spawn).toHaveBeenCalledOnce();
  });
  it.each(['exit', 'error', 'stdin'])('fängt %s ab und gibt dem Neustart wieder Kaltstartzeit', async failure => {
    vi.useFakeTimers(); const proc = child(); const next = child(); const spawn = vi.fn().mockReturnValueOnce(proc).mockReturnValueOnce(next);
    const helper = focus({ spawnImpl: spawn }); const capture = helper.capture();
    if (failure === 'exit') proc.emit('exit', 1);
    if (failure === 'error') proc.emit('error', Error('ENOENT'));
    if (failure === 'stdin') proc.stdin.emit('error', Error('EPIPE'));
    expect(await capture).toBeNull();
    let ready = false; const retry = helper.capture().then(value => { ready = true; return value; });
    await vi.advanceTimersByTimeAsync(3000); expect(ready).toBe(false);
    next.stdout.write('2 456\n'); expect(await retry).toBe('456'); expect(spawn).toHaveBeenCalledTimes(2);
  });
  it('lehnt ungültige Fensterhandles ohne PowerShell-Ausführung ab', async () => {
    const spawn = vi.fn(); const helper = focus({ spawnImpl: spawn });
    expect(await helper.restore('1; bad-command')).toBe(false); expect(await helper.restore('0')).toBe(false);
    expect(spawn).not.toHaveBeenCalled();
  });
  it.each(['focus denied', 'no hook', 'key error', 'success', 'no target', 'helper unavailable', 'helper throws'])('%s: genau ein Fokusversuch, bei fehlendem Helfer aktuelles Fenster', async mode => {
    const clipboard = { writeText: vi.fn() }; const hook = { keyTap: vi.fn(() => { if (mode === 'key error') throw Error('native'); }) };
    const helper = { restore: vi.fn(async () => {
      if (mode === 'helper throws') throw Error('unavailable');
      if (mode === 'helper unavailable') return null;
      return mode !== 'focus denied';
    }), capture: vi.fn() };
    const result = await pasteWindows({ text: 'Geheim', target: mode === 'no target' ? null : '123', clipboard, focus: helper, hook: mode === 'no hook' ? null : hook });
    expect(clipboard.writeText).toHaveBeenCalledWith('Geheim');
    const success = !['focus denied', 'no hook', 'key error'].includes(mode);
    expect(result).toBe(success);
    if (success) expect(hook.keyTap).toHaveBeenCalledWith(47, [29]);
    if (mode === 'focus denied' || mode === 'no hook') expect(hook.keyTap).not.toHaveBeenCalled();
    expect(helper.restore).toHaveBeenCalledTimes(mode === 'no target' || mode === 'no hook' ? 0 : 1);
    expect(helper.capture).not.toHaveBeenCalled();
  });
});
