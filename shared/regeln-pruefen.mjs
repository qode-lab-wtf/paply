#!/usr/bin/env node
// Prüft, ob Mac/Windows, iOS und Android zu REGELN.md passen. Ändert nichts.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const WURZEL = join(dirname(fileURLToPath(import.meta.url)), '..');
const lies = datei => readFileSync(join(WURZEL, datei), 'utf8');
const gibtEs = datei => existsSync(join(WURZEL, datei));

const DESKTOP = 'electron-menubar';
const IOS = 'ios/PaplyKit/Sources/PaplyKit';
const ANDROID = 'android/core/src/main/kotlin/com/paply/core';
const GEDANKEN = 'android/thoughts/src/main/kotlin/com/paply/thoughts';

// Wert aus REGELN.md → wo er in den Apps steht.
const WERTE = {
  'sprache.kurz_sekunden': [
    [`${DESKTOP}/dictation/language-guard.js`, /SHORT_SPEECH_SECONDS = ([\d.]+)/],
    [`${IOS}/Text/LanguageGuard.swift`, /shortSpeechSeconds = ([\d.]+)/],
    [`${ANDROID}/LanguageGuard.kt`, /shortSpeechSeconds = ([\d.]+)/],
  ],
  'sprache.abstand': [
    [`${DESKTOP}/dictation/language-guard.js`, /CHECK_GAP = ([\d.]+)/],
    [`${IOS}/Text/LanguageGuard.swift`, /checkGap = ([\d.]+)/],
    [`${ANDROID}/LanguageGuard.kt`, /checkGap = ([\d.]+)/],
  ],
  'begriffe.abstand': [
    [`${DESKTOP}/dictation/term-guard.js`, /TERM_GAP = ([\d.]+)/],
    [`${IOS}/Text/TermGuard.swift`, /gap = ([\d.]+)/],
    [`${ANDROID}/TermGuard.kt`, /gap = ([\d.]+)/],
  ],
  'diktat.whisper_modell': [
    [`${DESKTOP}/dictation/language-guard.js`, /WHISPER_MODEL = '([^']+)'/],
    [`${IOS}/PublicAPI.swift`, /transcriptionModel = "([^"]+)"/],
    [`${ANDROID}/GroqModels.kt`, /const val whisper = "([^"]+)"/],
    ['android/app/src/main/java/com/paply/android/settings/SettingsRepository.kt', /val transcriptionModel: String = "([^"]+)"/],
  ],
  'polieren.modell': [
    [`${DESKTOP}/dictation/groq-models.js`, /POLISH_MODEL = '([^']+)'/],
    [`${IOS}/PublicAPI.swift`, /polishModel = "([^"]+)"/],
    [`${ANDROID}/GroqModels.kt`, /const val polish = "([^"]+)"/],
  ],
  'polieren.ausweichmodell': [
    [`${DESKTOP}/dictation/groq-models.js`, /POLISH_FALLBACK_MODEL = '([^']+)'/],
    [`${IOS}/PublicAPI.swift`, /fallbackPolishModel = "([^"]+)"/],
    [`${ANDROID}/GroqModels.kt`, /const val polishFallback = "([^"]+)"/],
  ],
  'stille.no_speech_prob': [
    [`${DESKTOP}/audio/silence-filter.js`, /NO_SPEECH_PROB = ([\d.-]+)/],
    [`${IOS}/Audio/SilenceFilter.swift`, /static let noSpeechProb = ([\d.-]+)/],
    [`${ANDROID}/SilenceFilter.kt`, /const val noSpeechProb = ([\d.-]+)/],
  ],
  'stille.avg_logprob': [
    [`${DESKTOP}/audio/silence-filter.js`, /LOW_LOGPROB = ([\d.-]+)/],
    [`${IOS}/Audio/SilenceFilter.swift`, /static let lowLogprob = ([\d.-]+)/],
    [`${ANDROID}/SilenceFilter.kt`, /const val lowLogprob = ([\d.-]+)/],
  ],
  'gedanken.modell': [
    [`${DESKTOP}/notes/groq.js`, /PRIMARY_MODEL = '([^']+)'/],
    [`${IOS}/Thoughts/AI/ThoughtStructurer.swift`, /primaryModel = "([^"]+)"/],
    [`${GEDANKEN}/ai/ThoughtStructurer.kt`, /primaryModel = "([^"]+)"/],
  ],
  'gedanken.ausweichmodell': [
    [`${DESKTOP}/notes/groq.js`, /FALLBACK_MODEL = '([^']+)'/],
    [`${IOS}/Thoughts/AI/ThoughtStructurer.swift`, /fallbackModel = "([^"]+)"/],
    [`${GEDANKEN}/ai/ThoughtStructurer.kt`, /fallbackModel = "([^"]+)"/],
  ],
  'gedanken.regel_version': [
    [`${DESKTOP}/notes/prompt.js`, /VERSION = (\d+)/],
    [`${IOS}/Thoughts/AI/ThoughtPrompt.swift`, /static let version = (\d+)/],
    [`${GEDANKEN}/ai/ThoughtPrompt.kt`, /const val version = (\d+)/],
  ],
  'gedanken.grenze_sekunden': [
    ['ios/App/Session/ThoughtCapture.swift', /static let limit: TimeInterval = (\d+ \* \d+)/],
    ['android/app/src/main/java/com/paply/android/AudioCapture.kt', /maxMs: Long = ([\d_ *]+)L/],
  ],
};

// Ausnahme aus REGELN.md → woran man im Code erkennt, dass sie noch besteht.
const AUSNAHMEN = {
  A1: () => !gibtEs(`${DESKTOP}/dictation/language-guard.js`)
    || lies(`${DESKTOP}/notes/groq.js`).includes("form.append('language', 'de')"),
  A2: () => lies(`${DESKTOP}/electron-main.js`).includes("formData.append('model', 'whisper-large-v3-turbo')"),
  A3: () => !lies(`${DESKTOP}/audio/silence-filter.js`).includes('Merci'),
  A4: () => /func redoLanguage/.test(lies(`${IOS}/Text/LanguageGuard.swift`))
    || /fun redoLanguage/.test(lies(`${ANDROID}/LanguageGuard.kt`)),
  A5: () => !gibtEs(`${DESKTOP}/notes/thought.js`) || !lies(`${DESKTOP}/notes/queue.js`).includes("require('./thought')") || !lies(`${DESKTOP}/src/apps/notes/NotesApp.tsx`).includes('Aufgaben'),
  A6: () => !lies(`${DESKTOP}/electron-main.js`).includes('enablePolish: true')
    || !lies(`${DESKTOP}/src/components/DeveloperSettings.tsx`).includes('count.current >= 5')
    || !lies(`${DESKTOP}/src/components/DeveloperSettings.tsx`).includes('whisperModel')
    || !lies(`${DESKTOP}/src/components/DeveloperSettings.tsx`).includes('showDiagnosticLog')
    || /onCheckedChange=.*enablePolish/.test(lies(`${DESKTOP}/src/apps/dashboard/Dashboard.tsx`) + lies(`${DESKTOP}/src/apps/settings/SettingsApp.tsx`)),
  A7: () => /RETENTION_MS\s*=\s*7\s*\*/.test(lies(`${DESKTOP}/meeting/audio-retention.js`)) || /<audio\b/.test(lies(`${DESKTOP}/src/apps/dashboard/views/MeetingDetail.tsx`)) || /<audio\b/.test(lies(`${DESKTOP}/src/apps/notes/NotesApp.tsx`)) || /7\s*\*\s*86400000/.test(lies(`${DESKTOP}/notes/queue.js`)),
  A8: () => !gibtEs('android/thoughts/src/main/kotlin/com/paply/conversations') && !gibtEs('android/conversations'),
  A9: () => gibtEs(`${DESKTOP}/meeting/gemini-audio.js`),
  A10: () => lies(`${GEDANKEN}/local/EmbeddingIndex.kt`).includes('override val available = false'),
  A11: () => lies(`${DESKTOP}/dictation/custom-agent-prompt.js`).includes('Übersetze den finalen Text'),
  A12: () => lies(`${DESKTOP}/notes/capture.js`).includes('30 * 60000'),
  A14: () => gibtEs('ios/App/Conversations/ConversationLearning.swift'),
  A13: () => lies(`${IOS}/Conversations/ConversationSummarizer.swift`).includes('knapp auf Deutsch'),
};

const zahl = text => Number(String(text).replace(/_/g, '').split('*').reduce((a, b) => a * Number(b), 1));
const gleich = (a, b) => (Number.isFinite(zahl(a)) && Number.isFinite(zahl(b)) ? zahl(a) === zahl(b) : a === b);
// AudioCapture zählt Millisekunden, alle anderen Grenzen Sekunden.
const inRegelEinheit = (datei, wert) => (datei.endsWith('AudioCapture.kt') ? zahl(wert) / 1000 : wert);

function pruefeWerte(regeln, fehler) {
  const werte = Object.fromEntries([...regeln.matchAll(/^\| `([a-z_.]+)` \| `([^`]+)` \|/gm)].map(m => [m[1], m[2]]));
  for (const [schluessel, stellen] of Object.entries(WERTE)) {
    if (!(schluessel in werte)) { fehler.push(`${schluessel} fehlt in REGELN.md`); continue; }
    for (const [datei, muster] of stellen) {
      const treffer = lies(datei).match(muster);
      if (!treffer) fehler.push(`${schluessel}: in ${datei} nicht gefunden`);
      else if (!gleich(inRegelEinheit(datei, treffer[1]), werte[schluessel])) {
        fehler.push(`${schluessel}: ${datei} hat ${treffer[1]}, REGELN.md sagt ${werte[schluessel]}`);
      }
    }
  }
  for (const schluessel of Object.keys(werte)) {
    if (!(schluessel in WERTE)) fehler.push(`${schluessel} steht in REGELN.md, wird aber nicht geprüft`);
  }
}

function pruefeAusnahmen(regeln, fehler) {
  const eingetragen = new Set([...regeln.matchAll(/^\| (A\d+) \|/gm)].map(m => m[1]));
  for (const [nummer, bestehtNoch] of Object.entries(AUSNAHMEN)) {
    if (!eingetragen.has(nummer)) {
      if (bestehtNoch()) fehler.push(`${nummer} besteht im Code, fehlt aber in REGELN.md`);
    } else if (!bestehtNoch()) fehler.push(`${nummer} ist behoben: aus REGELN.md streichen`);
  }
  for (const nummer of eingetragen) {
    if (!(nummer in AUSNAHMEN)) fehler.push(`${nummer} steht in REGELN.md, wird aber nicht geprüft`);
  }
  return eingetragen.size;
}

function pruefePolierPrompt(fehler) {
  const quelle = lies('shared/polish/system-prompt.txt');
  const desktop = lies(`${DESKTOP}/dictation/polish-prompt.js`).match(/POLISH_SYSTEM_PROMPT = ("(?:[^"\\]|\\.)*");/);
  const ios = lies(`${IOS}/Text/PolishPrompt.swift`).match(/systemPrompt = """\n([\s\S]*?)\n\s*"""/);
  const android = lies(`${ANDROID}/PolishPrompt.kt`).match(/"""([\s\S]*?)"""/);
  const kopien = {
    'Mac/Windows': desktop && JSON.parse(desktop[1]),
    iOS: ios && ios[1].replace(/^ {4}/gm, ''),
    Android: android && android[1],
  };
  for (const [app, text] of Object.entries(kopien)) {
    if (text !== quelle) fehler.push(`Polier-Prompt in ${app} weicht von shared/polish/system-prompt.txt ab`);
  }
}

function pruefeGedankenPrompt(fehler) {
  // Android prüft seinen Text in AILedgerPromptTests gegen dieselbe Datei.
  const ios = [...lies(`${IOS}/Thoughts/AI/ThoughtPrompt.swift`).matchAll(/static let \w+ = """\n([\s\S]*?)\n\s*"""/g)]
    .map(m => m[1].replace(/^ {4}/gm, '')).join('\n\n');
  const quelle = lies('shared/gedanken/system-prompt-v6.txt');
  const desktop = lies(`${DESKTOP}/notes/prompt.js`).match(/PROMPT = ("(?:[^"\\]|\\.)*");/);
  if (!desktop || JSON.parse(desktop[1]) !== quelle) fehler.push('Desktop-Gedanken-Prompt weicht ab');
  const android = [...lies(`${GEDANKEN}/ai/ThoughtPrompt.kt`).matchAll(/const val (?:intro|\w+Rules) =\s*("(?:[^"\\]|\\.)*")/g)].map(m => JSON.parse(m[1])).join('\n\n');
  if (android.trimEnd() !== quelle.trimEnd()) fehler.push('Android-Gedanken-Prompt weicht ab');
  if (lies('android/thoughts/src/test/resources/thought-system-v6.txt') !== quelle || ios !== quelle.trimEnd()) {
    fehler.push('Gedanken-Prompt von iOS und Android weicht ab');
  }
}

function pruefeGedankenGrenze(fehler) {
  // Die Voreinstellung von AudioCapture gilt nur, solange ThoughtService keine eigene Grenze übergibt.
  if (/AudioCapture\([^\n]*maxMs/.test(lies('android/app/src/main/java/com/paply/android/ThoughtService.kt'))) {
    fehler.push('gedanken.grenze_sekunden: ThoughtService übergibt eine eigene Grenze');
  }
}

function pruefeStilleListe(fehler) {
  const saetze = (text, anfang) => {
    const start = text.indexOf(anfang);
    const ende = text.indexOf('artifact', start);
    return [...text.slice(start, ende).split('\n').filter(z => !z.trim().startsWith('//')).join('\n').matchAll(/"([^"]+)"/g)]
      .map(m => m[1]).sort();
  };
  const ios = saetze(lies(`${IOS}/Audio/SilenceFilter.swift`), 'silencePhrases');
  const android = saetze(lies(`${ANDROID}/SilenceFilter.kt`), 'silencePhrases');
  const desktop = JSON.parse(lies(`${DESKTOP}/audio/silence-filter.js`).match(/SILENCE_PHRASES = new Set\((\[[\s\S]*?\])\.map/)[1]).sort();
  if (desktop.join('|') !== ios.join('|')) fehler.push('Desktop-Stille-Liste weicht von iOS ab');
  if (ios.length === 0 || ios.join('|') !== android.join('|')) fehler.push('Stille-Liste von iOS und Android weicht ab');
}

function pruefeSprachfaelle(fehler) {
  const faelle = JSON.parse(lies('shared/sprache/faelle.json'));
  const felder = ['name', 'spoken', 'expected', 'detected', 'users', 'check', 'result'];
  for (const fall of faelle) {
    if (felder.some(feld => !(feld in fall))) fehler.push(`Sprachfall unvollständig: ${fall.name}`);
    if (fall.result !== 'detected' && fall.result !== 'expected') fehler.push(`Sprachfall ohne gültiges Ergebnis: ${fall.name}`);
  }
}

function pruefeProjektregeln(fehler) {
  if (lies('CLAUDE.md') !== lies('AGENTS.md')) fehler.push('CLAUDE.md und AGENTS.md müssen gleich sein');
}

const regeln = lies('REGELN.md');
const fehler = [];
pruefeWerte(regeln, fehler);
const ausnahmen = pruefeAusnahmen(regeln, fehler);
pruefePolierPrompt(fehler);
pruefeGedankenPrompt(fehler);
pruefeGedankenGrenze(fehler);
pruefeStilleListe(fehler);
pruefeSprachfaelle(fehler);
pruefeProjektregeln(fehler);

if (fehler.length) {
  console.error(`Regeln verletzt (${fehler.length}):`);
  for (const zeile of fehler) console.error(`- ${zeile}`);
  process.exit(1);
}
console.log(`Regeln eingehalten: ${Object.keys(WERTE).length} Werte, 3 Polier-Prompts, Gedanken-Prompt, Stille-Liste. Offene Ausnahmen: ${ausnahmen}.`);
