#!/usr/bin/env node
// Creates synthetic audio only outside the repo; never starts Electron.
import { mkdir, realpath, unlink, access } from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { writeJson } from './api.mjs';
const data = path.resolve(process.argv[2] || '/tmp/paply-bench-dev');
await mkdir(data, { recursive: true, mode: 0o700 });
const repo = await realpath(new URL('../../../', import.meta.url));
const relative = path.relative(repo, await realpath(data));
if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) throw new Error('Fixture-Ordner muss außerhalb des Repositorys liegen.');
const examples = [
  { id: 'dev-01', text: 'Bitte ändere die API in React und TypeScript. Der Branch heißt Benchmark. Keine neuen Abhängigkeiten hinzufügen.' },
  { id: 'dev-02', text: 'Also, ähm, wir treffen uns am Dienstag, nein Mittwoch, um fünfzehn Uhr. Frau Müller bringt drei, drei Unterlagen mit.' },
  { id: 'dev-03', text: 'Bitte lösche die Datei nicht. Ich möchte nur die Vorschau sehen. Der Betrag ist zweiundvierzig Euro, nicht vierundzwanzig Euro.' },
];
// Refuse to overwrite existing fixtures or references.
for (const file of ['references.json', 'scripts.json', ...examples.flatMap(e => [e.id + '.wav', e.id + '.json'])]) {
  try { await access(path.join(data, file)); throw new Error(`Datei existiert bereits: ${file}; anderen Datenordner wählen.`); }
  catch (e) { if (e.code !== 'ENOENT') throw e; }
}
const refs = {};
for (const [i, e] of examples.entries()) {
  const aiff = path.join(data, e.id + '.aiff');
  for (const [bin, args] of [
    ['/usr/bin/say', ['-v', 'Anna', '-r', '165', '-o', aiff, e.text]],
    ['/usr/bin/afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', aiff, path.join(data, e.id + '.wav')]],
  ]) {
    const p = spawnSync(bin, args, { encoding: 'utf8' });
    if (p.status !== 0) throw new Error(`${bin} fehlgeschlagen: ${p.stderr || p.error?.message}`);
  }
  await unlink(aiff);
  await writeJson(path.join(data, e.id + '.json'), { id: e.id, createdAt: new Date().toISOString(), language: 'de', enablePolish: true, activeProfile: 'coding', skipped: false, voiceActivity: null, transcript: null, polished: null, finalText: null, synthetic: true });
  refs[e.id] = { text: e.text, ideal: i === 1 ? 'Wir treffen uns am Mittwoch um fünfzehn Uhr. Frau Müller bringt drei Unterlagen mit.' : e.text, kind: 'vorgelesen', note: `Synthetische Anna-Stimme, Probe ${i + 1}. Keine Alltagssprache/realen Mikrofonbedingungen.` };
}
await writeJson(path.join(data, 'references.json'), refs);
await writeJson(path.join(data, 'scripts.json'), examples.map((e, i) => ({ nr: i + 1, text: e.text })));
console.log(`Drei WAV-Proben erstellt: ${data}`);
