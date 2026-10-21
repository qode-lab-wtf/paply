import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
const { createMeetingStore } = require('./meeting-store.js');

function fakeStore() {
  const data = { meetings: [] };
  return { get: (k) => data[k], set: (k, v) => { data[k] = v; } };
}

describe('MeetingStore', () => {
  let baseDir, store, ms;
  beforeEach(() => {
    baseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-meet-'));
    store = fakeStore();
    ms = createMeetingStore({ baseDir, store });
  });
  it('create legt Ordner + Index an', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    expect(fs.existsSync(path.join(baseDir, id, 'chunks'))).toBe(true);
    expect(ms.list().length).toBe(1);
    expect(ms.list()[0].id).toBe(id);
  });
  it('saveTranscript + get liefert Segmente', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    ms.saveTranscript(id, { segments: [{ tStart: 0, tEnd: 1, speaker: 'me', channel: 'mic', text: 'Hi' }], language: 'de' });
    expect(ms.get(id).transcript.segments[0].text).toBe('Hi');
  });
  it('toggleTodo schaltet erledigt um', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    ms.saveSummary(id, { kurzzusammenfassung: '', kernpunkte: [], todos: [{ text: 'X', verantwortlich: null, erledigt: false }], offeneFragen: [], generatedAt: '', model: '' });
    ms.toggleTodo(id, 0);
    expect(ms.get(id).summary.todos[0].erledigt).toBe(true);
  });
  it('renameSpeaker benennt EIN Label um und aktualisiert speakerCount', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    ms.saveTranscript(id, { segments: [
      { tStart: 0, tEnd: 1, speaker: 'Sprecher 1', channel: 'system', text: 'A' },
      { tStart: 1, tEnd: 2, speaker: 'Sprecher 2', channel: 'system', text: 'B' },
      { tStart: 2, tEnd: 3, speaker: 'me', channel: 'mic', text: 'C' },
    ], language: 'de' });

    expect(ms.renameSpeaker(id, 'Sprecher 1', 'Max')).toBe(true);
    let segs = ms.get(id).transcript.segments;
    expect(segs.find((s) => s.text === 'A').speaker).toBe('Max');
    expect(segs.find((s) => s.text === 'B').speaker).toBe('Sprecher 2'); // unberührt
    expect(ms.list().find((e) => e.id === id).speakerCount).toBe(3);
  });

  it('renameSpeaker tauscht den Namen auch im Protokoll + speichert speakerNames im Index', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    ms.saveTranscript(id, { segments: [
      { tStart: 0, tEnd: 1, speaker: 'Sprecher 1', channel: 'mic', text: 'Hallo' },
      { tStart: 1, tEnd: 2, speaker: 'Sprecher 2', channel: 'mic', text: 'Tag' },
    ], language: 'de' });
    ms.saveSummary(id, {
      kurzzusammenfassung: 'Sprecher 1 begrüßt Sprecher 2.',
      kernpunkte: ['Sprecher 1 fragt nach.'],
      todos: [{ text: 'Sprecher 2 meldet sich', verantwortlich: 'Sprecher 2', erledigt: false }],
      offeneFragen: [], generatedAt: '', model: '',
    });

    expect(ms.renameSpeaker(id, 'Sprecher 1', 'Allan')).toBe(true);
    expect(ms.renameSpeaker(id, 'Sprecher 2', 'Alex')).toBe(true);

    const full = ms.get(id);
    // Protokoll-Platzhalter ersetzt (ohne Neu-Erzeugung)
    expect(full.summary.kurzzusammenfassung).toBe('Allan begrüßt Alex.');
    expect(full.summary.kernpunkte[0]).toBe('Allan fragt nach.');
    expect(full.summary.todos[0].verantwortlich).toBe('Alex');
    // Index trägt die Namen → Listenansicht zeigt sie
    expect(full.index.speakerNames).toEqual(['Allan', 'Alex']);
  });

  it('renameSpeaker führt zwei Sprecher zusammen (Merge) wenn gleicher Name', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    ms.saveTranscript(id, { segments: [
      { tStart: 0, tEnd: 1, speaker: 'Sprecher 1', channel: 'system', text: 'A' },
      { tStart: 1, tEnd: 2, speaker: 'Sprecher 2', channel: 'system', text: 'B' },
    ], language: 'de' });
    ms.renameSpeaker(id, 'Sprecher 1', 'Gegenstelle');
    ms.renameSpeaker(id, 'Sprecher 2', 'Gegenstelle');
    const segs = ms.get(id).transcript.segments;
    expect(new Set(segs.map((s) => s.speaker)).size).toBe(1);
    expect(ms.list().find((e) => e.id === id).speakerCount).toBe(1);
  });

  it('renameSpeaker liefert false, wenn das Label nicht vorkommt', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    ms.saveTranscript(id, { segments: [{ tStart: 0, tEnd: 1, speaker: 'me', channel: 'mic', text: 'X' }], language: 'de' });
    expect(ms.renameSpeaker(id, 'Sprecher 9', 'Y')).toBe(false);
  });

  it('remove löscht Ordner + Index', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    expect(ms.remove(id)).toBe(true);
    expect(ms.list().length).toBe(0);
    expect(fs.existsSync(path.join(baseDir, id))).toBe(false);
  });
});

describe('MeetingStore: sichere Dateigrenzen', () => {
  let temp, baseDir, outside, store, ms;
  beforeEach(() => {
    temp = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-meet-path-'));
    baseDir = path.join(temp, 'meetings');
    outside = path.join(temp, 'outside');
    fs.mkdirSync(outside);
    fs.writeFileSync(path.join(outside, 'transcript.json'), JSON.stringify({ segments: [{ speaker: 'Sprecher 1' }] }));
    fs.writeFileSync(path.join(outside, 'summary.json'), JSON.stringify({ todos: [{ erledigt: false }] }));
    store = fakeStore();
    ms = createMeetingStore({ baseDir, store });
  });
  afterEach(() => fs.rmSync(temp, { recursive: true, force: true }));

  it.each(['../outside', '..\\outside', '/outside', 'C:\\outside', '.', '', null])('blockiert Pfad-IDs %s auch in manipuliertem Index', id => {
    store.set('meetings', [{ id }]);
    const transcript = fs.readFileSync(path.join(outside, 'transcript.json'), 'utf8');
    const summary = fs.readFileSync(path.join(outside, 'summary.json'), 'utf8');
    const operations = [
      () => ms.renameSpeaker(id, 'Sprecher 1', 'Fremd'), () => ms.toggleTodo(id, 0),
      () => ms.loadTranscript(id), () => ms.saveTranscript(id, {}), () => ms.saveSummary(id, {}),
      () => ms.meetingDir(id), () => ms.chunkPath(id, 'mic', 0), () => ms.audioPath(id, 'mic'),
      () => ms.get(id), () => ms.remove(id), () => ms.finalizeIndex(id, { title: 'Fremd' }),
    ];
    for (const operation of operations) expect(operation).toThrow();
    expect(fs.readFileSync(path.join(outside, 'transcript.json'), 'utf8')).toBe(transcript);
    expect(fs.readFileSync(path.join(outside, 'summary.json'), 'utf8')).toBe(summary);
  });

  it('verweigert den Zugriff auf nicht indexierte Meeting-Ordner', () => {
    fs.mkdirSync(path.join(baseDir, 'orphan'), { recursive: true });
    expect(() => ms.saveTranscript('orphan', {})).toThrow('nicht gefunden');
    expect(() => ms.renameSpeaker('orphan', 'A', 'B')).toThrow('nicht gefunden');
    expect(() => ms.toggleTodo('orphan', 0)).toThrow('nicht gefunden');
    expect(() => ms.meetingDir('orphan')).toThrow('nicht gefunden');
    expect(ms.get('orphan')).toBe(null);
    expect(ms.remove('orphan')).toBe(false);
  });

  it('blockiert Datei-Symlinks nach außen', ({ skip }) => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    try {
      fs.symlinkSync(path.join(outside, 'transcript.json'), path.join(ms.meetingDir(id), 'transcript.json'));
    } catch (error) {
      // Windows erlaubt Datei-Symlinks ohne Entwicklermodus/Adminrechte nicht.
      if (process.platform === 'win32' && error.code === 'EPERM') { skip(); return; }
      throw error;
    }
    expect(() => ms.renameSpeaker(id, 'Sprecher 1', 'Fremd')).toThrow('symbolischen Link');
    expect(() => ms.saveTranscript(id, {})).toThrow('symbolischen Link');
  });

  it('blockiert Verzeichnis-Symlinks/Junctions nach außen', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    fs.rmSync(ms.meetingDir(id), { recursive: true });
    fs.symlinkSync(outside, path.join(baseDir, id), 'junction');
    expect(() => ms.remove(id)).toThrow('symbolischen Link');
    expect(() => ms.get(id)).toThrow('symbolischen Link');
    expect(fs.existsSync(path.join(outside, 'transcript.json'))).toBe(true);
  });

  it('validiert Audiokanäle und Chunk-Nummern und verhindert Index-ID-Änderungen', () => {
    const id = ms.create('2026-06-08T10:00:00.000Z');
    expect(() => ms.chunkPath(id, '../../outside', 0)).toThrow('Audiokanal');
    expect(() => ms.chunkPath(id, 'mic', '../outside')).toThrow('Chunk-Nummer');
    expect(() => ms.audioPath(id, '../outside')).toThrow('Audiokanal');
    ms.finalizeIndex(id, { id: '../outside', title: 'Neuer Titel' });
    expect(ms.list()[0]).toMatchObject({ id, title: 'Neuer Titel' });
  });
});
