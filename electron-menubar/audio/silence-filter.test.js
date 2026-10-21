import { describe, it, expect } from 'vitest';
import { filterTranscription, shouldSkipTranscription, validateVoiceActivity } from './silence-filter.js';

const silence = { durationMs: 4000, measuredMs: 4000, speechMs: 0, peakDbfs: -90, maxGapMs: 40 };
const speech = { ...silence, speechMs: 400, peakDbfs: -35 };
const segment = (text, no_speech_prob = 0.01, avg_logprob = -0.1) => ({ text, no_speech_prob, avg_logprob });

describe('Diktat-Stillefilter', () => {
  it('überspringt Groq nur bei vollständig gemessener Aufnahme mit nahezu keiner leisen Aktivität', () => {
    expect(shouldSkipTranscription(silence)).toBe(true);
    expect(shouldSkipTranscription(speech)).toBe(false);
    expect(shouldSkipTranscription({ ...silence, speechMs: 40, peakDbfs: -62 })).toBe(true);
    expect(shouldSkipTranscription({ ...silence, speechMs: 80, peakDbfs: -62 })).toBe(false);
    expect(shouldSkipTranscription({ ...silence, speechMs: 40, peakDbfs: -35 })).toBe(false);
    expect(shouldSkipTranscription({ ...silence, peakDbfs: -60 })).toBe(false);
    expect(shouldSkipTranscription({ ...silence, peakDbfs: -120 })).toBe(true);
  });

  it('verwendet absolute Sprachdauer, damit lange Pausen echte Sprache nicht verdünnen', () => {
    const meta = { ...silence, durationMs: 60000, measuredMs: 60000, speechMs: 400, peakDbfs: -64 };
    expect(shouldSkipTranscription(meta)).toBe(false);
    expect(filterTranscription({ text: 'Vielen Dank.' }, meta).text).toBe('Vielen Dank.');
  });

  it.each([
    undefined, null, {}, { ...silence, durationMs: 300, measuredMs: 300 },
    { ...silence, measuredMs: 3000 }, { ...silence, maxGapMs: 120 },
    { ...silence, speechMs: -1 }, { ...silence, measuredMs: 5000 },
    { ...silence, peakDbfs: NaN }, { ...silence, peakDbfs: null },
    { ...silence, durationMs: Infinity }, { ...silence, speechMs: '0' },
  ])('verwirft bei fehlenden, kurzen oder unzuverlässigen Messungen nichts vorab (%j)', meta => {
    expect(shouldSkipTranscription(meta)).toBe(false);
    expect(filterTranscription({ text: 'Vielen Dank.' }, meta).text).toBe('Vielen Dank.');
  });

  it('behält absichtlich diktierte Dankesformeln mit Sprachaktivität', () => {
    expect(filterTranscription({ text: 'Vielen Dank.' }, speech).text).toBe('Vielen Dank.');
    expect(filterTranscription({ text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0.99)] }, speech).text).toBe('Vielen Dank.');
  });

  it.each([
    'Vielen Dank.', 'DANKE!!!', 'Bis zum nächsten Mal.', 'Tschüss.',
    'Thank you.', 'Thanks for watching!', '  Vielen  Dank!  ',
  ])('verwirft bekannte vollständige Phrasen mit gemessener Stille: %s', text => {
    expect(filterTranscription({ text }, silence)).toMatchObject({ text: '', reason: 'known-silence-phrase' });
    expect(filterTranscription({ text }).text).toBe(text.trim());
  });

  it.each([
    'Untertitel im Auftrag des ZDF, 2017', 'Untertitelung des ZDF für funk',
    'Untertitel im Auftrag des ZDF für funk, 2024', 'Amara.org',
    'Untertitel von der Amara.org-Community', 'Copyright', 'Copyright WDR 2023',
  ])('verwirft eindeutige vollständige Artefakte auch ohne Metadaten: %s', text => {
    expect(filterTranscription({ text }).reason).toBe('known-artifact-phrase');
    expect(filterTranscription({ text }).text).toBe('');
    expect(filterTranscription({ text }, speech).text).toBe('');
  });

  it('verwirft keine bloßen Erwähnungen von Untertiteln, Amara oder Copyright', () => {
    for (const text of ['Bitte Untertitel aktivieren.', 'Öffne Amara.org.', 'Bitte das Copyright im Dokument ergänzen.']) {
      expect(filterTranscription({ text }).text).toBe(text);
    }
  });

  it('nutzt für mehrdeutige Phrasen die Grenze unter 400 ms gemessener Aktivität', () => {
    const response = { text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0, -0.28)] };
    expect(filterTranscription(response, { ...speech, speechMs: 399 }).text).toBe('');
    expect(filterTranscription(response, { ...speech, speechMs: 400 }).text).toBe('Vielen Dank.');
    expect(filterTranscription(response).text).toBe('Vielen Dank.');
    expect(filterTranscription(response, { ...speech, speechMs: 100, measuredMs: 2000 }).text).toBe('Vielen Dank.');
  });

  it('trennt die gemessenen Groq-Stille- und Sprachantworten bei no_speech_prob=0 nur anhand der Aktivität', () => {
    const digitalSilence = { text: ' Vielen Dank.', segments: [segment(' Vielen Dank.', 0, -0.28)] };
    const spokenThanks = { text: ' Vielen Dank.', segments: [segment(' Vielen Dank.', 0, -0.224)] };
    expect(filterTranscription(digitalSilence, silence).text).toBe('');
    expect(filterTranscription(spokenThanks, speech).text).toBe('Vielen Dank.');
    // Ohne Pegeldaten liefert weder Konfidenz eine sichere Unterscheidung.
    expect(filterTranscription(digitalSilence).text).toBe('Vielen Dank.');
    expect(filterTranscription(spokenThanks).text).toBe('Vielen Dank.');
    const text = 'Bitte schick mir die Unterlagen, vielen Dank.';
    expect(filterTranscription({ text, segments: [segment(text, 0, -0.059)] }, speech).text).toBe(text);
  });

  it.each([-0.715, -0.556])('behandelt Groq-Rauschantworten mit no_speech_prob=0 und avg_logprob=%s als leer', logprob => {
    expect(filterTranscription({ text: ' ...', segments: [segment(' ...', 0, logprob)] }).text).toBe('');
  });

  it('behält normales Diktat einschließlich Dankesformeln und ursprünglicher Formatierung', () => {
    const text = 'Bitte schick mir den Bericht.\nVielen Dank.';
    expect(filterTranscription({ text, segments: [segment('Bitte schick mir den Bericht.'), segment('Vielen Dank.')] }, silence).text).toBe(text);
    expect(filterTranscription({ text: 'Das ist ein normales Diktat.' }, silence).text).toBe('Das ist ein normales Diktat.');
  });

  it('entfernt bei gemischten Segmenten nur solche mit beiden Whisper-Stille-Signalen', () => {
    const response = { text: 'Bitte morgen antworten. Vielen Dank.', segments: [
      segment('Bitte morgen antworten.'), segment('Vielen Dank.', 0.95, -1.5),
    ] };
    expect(filterTranscription(response)).toEqual({ text: 'Bitte morgen antworten.', droppedSegments: 1, reason: null });
  });

  it('verwirft vollständige Stille anhand der Segmente auch ohne Renderer-Metadaten', () => {
    expect(filterTranscription({ text: 'Erfundener Text', segments: [segment('Erfundener Text', 0.8, -1.2)] }))
      .toEqual({ text: '', droppedSegments: 1, reason: 'no-speech-segments' });
  });

  it.each([[0.6, -1.5], [0.9, -1], [0.8, -0.1], [0.1, -2], [undefined, -2], [0.99, undefined], ['0.99', -2], [1.1, -2]])(
    'behält Segmente bei unzureichenden oder fehlenden Signalen (%s, %s)', (probability, logprob) => {
      const text = 'Hallo, hier ist mein Diktat.';
      expect(filterTranscription({ text, segments: [{ text, no_speech_prob: probability, avg_logprob: logprob }] }).text).toBe(text);
    }
  );

  it('filtert bekannte Phrasen ohne Renderer-Metadaten nur mit sehr hohem no_speech_prob', () => {
    expect(filterTranscription({ text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0.99)] }).text).toBe('');
    expect(filterTranscription({ text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0.7)] }).text).toBe('Vielen Dank.');
  });

  it('überträgt den Stille-Verdacht eines entfernten Segments nicht auf gesprochene Dankesformeln', () => {
    expect(filterTranscription({ text: 'Amara.org Vielen Dank.', segments: [
      segment('Amara.org', 0.99, -2), segment('Vielen Dank.', 0.01),
    ] }).text).toBe('Vielen Dank.');
  });

  it.each([undefined, [], null, [{ no_speech_prob: 0.99, avg_logprob: -2 }], [null]])(
    'fällt bei fehlenden oder unbrauchbaren Segmenten auf den bisherigen Text zurück (%j)', segments => {
      expect(filterTranscription({ text: 'Vielen Dank.', segments }).text).toBe('Vielen Dank.');
    }
  );

  it('nutzt vorhandene Segmente, falls nur der globale Text fehlt', () => {
    expect(filterTranscription({ segments: [segment('Bitte morgen antworten.')] }).text).toBe('Bitte morgen antworten.');
  });

  it('behält die bisherige Behandlung leerer und trivialer Ergebnisse', () => {
    for (const text of ['', '  ', '...', '?']) expect(filterTranscription({ text }).text).toBe('');
  });

  it('validiert auch aus JSON-Backups geladene Metadaten', () => {
    expect(validateVoiceActivity(JSON.parse(JSON.stringify(silence)))).toEqual(silence);
    expect(validateVoiceActivity({ ...silence, speechMs: 5000 })).toBeUndefined();
  });
});
