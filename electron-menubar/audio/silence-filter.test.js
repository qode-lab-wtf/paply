import { describe, it, expect } from 'vitest';
import { filterTranscription, shouldSkipTranscription, validateVoiceActivity } from './silence-filter.js';
import { measureVoiceActivity, summarizeVoiceActivity } from '../src/lib/voice-activity.ts';

const silence = { durationMs: 4000, measuredMs: 4000, speechMs: 0, peakDbfs: -90, floorDbfs: -90, maxGapMs: 40 };
const speech = { ...silence, speechMs: 400, peakDbfs: -35 };
const segment = (text, no_speech_prob = 0.01, avg_logprob = -0.1) => ({ text, no_speech_prob, avg_logprob });

// Vom Sample-Fenster bis zur Main-Entscheidung testen, statt speechMs für die
// Raum-/Sprachfälle vorzugeben. -Infinity erzeugt wirklich digitale Nullen.
function metaForLevels(levels) {
  return summarizeVoiceActivity(levels.map(dbfs => measureVoiceActivity(
    new Float32Array(128).fill(10 ** (dbfs / 20)), 40
  )));
}

describe('Relative Sprachaktivität unter realistischen Grundpegeln', () => {
  const thanks = { text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0, -0.28)] };

  it('überspringt 5 s stationäres Raumrauschen bei -50 dBFS ±2 dB', () => {
    const meta = metaForLevels(Array.from({ length: 125 }, (_, i) => -50 + (i % 5) - 2));
    expect(meta.floorDbfs).toBeCloseTo(-52);
    expect(meta.peakDbfs).toBeCloseTo(-48);
    expect(meta.speechMs).toBe(0);
    expect(shouldSkipTranscription(meta)).toBe(true);
  });

  it('behält 600 ms gesprochene Silben bei -25 dBFS über Raumrauschen von -50 dBFS', () => {
    const meta = metaForLevels([
      ...Array.from({ length: 110 }, (_, i) => -50 + (i % 5) - 2), ...Array(15).fill(-25),
    ]);
    expect(meta.speechMs).toBeGreaterThanOrEqual(400);
    expect(shouldSkipTranscription(meta)).toBe(false);
    expect(filterTranscription(thanks, meta).text).toBe('Vielen Dank.');
  });

  it('transkribiert einen 80-ms-Tastaturklick über -55 dBFS Rauschen, verwirft aber die Dankes-Halluzination', () => {
    const meta = metaForLevels([...Array(123).fill(-55), ...Array(2).fill(-30)]);
    expect(meta.speechMs).toBe(80);
    expect(meta.peakDbfs - meta.floorDbfs).toBeGreaterThan(10);
    expect(shouldSkipTranscription(meta)).toBe(false);
    expect(filterTranscription(thanks, meta).text).toBe('');
  });

  it.each([0, 5, 10])('behält Dauerrede ohne Pausen zwischen -35 und -15 dBFS (Phasenlage %i)', phase => {
    const meta = metaForLevels(Array.from({ length: 125 }, (_, i) => -35 + ((i + phase) % 21)));
    expect(meta.speechMs).toBeGreaterThanOrEqual(250);
    expect(shouldSkipTranscription(meta)).toBe(false);
    expect(filterTranscription(thanks, meta).text).toBe('Vielen Dank.');
    expect(filterTranscription({ text: 'Das ist ein zusammenhängendes Diktat ohne Pausen.' }, meta).text)
      .toBe('Das ist ein zusammenhängendes Diktat ohne Pausen.');
  });

  it('überspringt digitale Stille', () => {
    const meta = metaForLevels(Array(125).fill(-Infinity));
    expect(meta).toMatchObject({ floorDbfs: -120, peakDbfs: -120, speechMs: 0 });
    expect(shouldSkipTranscription(meta)).toBe(true);
  });

  it('behält Sprache von -28 bis -18 dBFS in einem lauten Café bei -40 dBFS ±4 dB', () => {
    const meta = metaForLevels([
      ...Array.from({ length: 110 }, (_, i) => -40 + (i % 9) - 4),
      ...Array.from({ length: 15 }, (_, i) => -28 + (i % 6) * 2),
    ]);
    expect(meta.speechMs).toBeGreaterThanOrEqual(400);
    expect(shouldSkipTranscription(meta)).toBe(false);
    expect(filterTranscription(thanks, meta).text).toBe('Vielen Dank.');
  });
});

describe('Diktat-Stillefilter', () => {
  it('überspringt Groq nur bei zuverlässiger Messung mit unter 80 ms Aktivität und weniger als 6 dB Dynamik', () => {
    expect(shouldSkipTranscription(silence)).toBe(true);
    expect(shouldSkipTranscription(speech)).toBe(false);
    expect(shouldSkipTranscription({ ...silence, speechMs: 79, peakDbfs: -85 })).toBe(true);
    expect(shouldSkipTranscription({ ...silence, speechMs: 80, peakDbfs: -85 })).toBe(false);
    expect(shouldSkipTranscription({ ...silence, speechMs: 40, peakDbfs: -35 })).toBe(false);
    expect(shouldSkipTranscription({ ...silence, peakDbfs: -80 })).toBe(false);
    expect(shouldSkipTranscription({ ...silence, peakDbfs: -120, floorDbfs: -120 })).toBe(true);
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
    { ...silence, floorDbfs: undefined }, { ...silence, floorDbfs: null },
    { ...silence, floorDbfs: -121 }, { ...silence, floorDbfs: -80 },
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

  it('nutzt für mehrdeutige Phrasen die Grenze unter 120 ms nur bei leisem Grundpegel', () => {
    const response = { text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0, -0.28)] };
    expect(filterTranscription(response, { ...speech, speechMs: 119 }).text).toBe('');
    expect(filterTranscription(response, { ...speech, speechMs: 120 }).text).toBe('Vielen Dank.');
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

  it('behält mehrdeutige Phrasen ohne Renderer-Metadaten auch bei hohem no_speech_prob allein', () => {
    expect(filterTranscription({ text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0.99)] }).text).toBe('Vielen Dank.');
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

  it('nutzt alte Metadaten ohne relativen Grundpegel nicht zum Verwerfen mehrdeutiger Phrasen', () => {
    const { floorDbfs, ...oldMeta } = silence;
    expect(validateVoiceActivity(oldMeta)).toBeUndefined();
    expect(shouldSkipTranscription(oldMeta)).toBe(false);
    expect(filterTranscription({ text: 'Vielen Dank.', segments: [segment('Vielen Dank.', 0.99)] }, oldMeta).text).toBe('Vielen Dank.');
    expect(filterTranscription({ text: 'Amara.org' }, oldMeta).text).toBe('');
  });
});

describe('Review R1: kurze echte Wörter und Grenzwerte', () => {
  it.each([
    ['Danke.', -60, -25, 200, 'Danke.'],
    ['Tschüss.', -60, -25, 240, 'Tschüss.'],
    ['Vielen Dank.', -35, -20, 40, 'Vielen Dank.'],
    ['Vielen Dank.', -70, -65, 0, ''],
    ['Vielen Dank.', -55, -30, 80, ''],
    ['Vielen Dank.', -50, -38, 119, ''],
    ['Vielen Dank.', -50, -38, 120, 'Vielen Dank.'],
    ['Vielen Dank.', -45, -30, 40, 'Vielen Dank.'],
    ['Vielen Dank.', -35, -24, 400, ''],
    ['Vielen Dank.', -35, -23, 40, 'Vielen Dank.'],
  ])('%s bei Grund %s / Spitze %s / Aktivität %s ms → %j', (text, floorDbfs, peakDbfs, speechMs, expected) => {
    const meta = { ...silence, durationMs: 600, measuredMs: 600, floorDbfs, peakDbfs, speechMs };
    expect(filterTranscription({ text }, meta).text).toBe(expected);
  });
  it.each([6, 7, 8, 9])('überspringt echte Dynamik von %s dB über Rauschen nicht', dynamic => {
    expect(shouldSkipTranscription({ ...silence, floorDbfs: -35, peakDbfs: -35 + dynamic, speechMs: 40 })).toBe(false);
  });
  it('behält kurze PTT-Aufnahmen ohne zuverlässige Messdauer', () => {
    expect(filterTranscription({ text: 'Danke.' }, { ...silence, durationMs: 300, measuredMs: 300, speechMs: 200, peakDbfs: -20 }).text).toBe('Danke.');
  });
  it('ignoriert beim Retry Phrase und Segment-Stille, aber weiterhin Artefakte und triviale Texte', () => {
    const options = { bypassLocalFilters: true };
    const response = { text: 'Danke.', segments: [segment('Danke.', 0.99, -2)] };
    expect(filterTranscription(response, silence, options)).toMatchObject({ text: 'Danke.', droppedSegments: 0, reason: null });
    for (const text of ['Amara.org', 'Untertitel im Auftrag des ZDF, 2017', 'Copyright WDR 2023', '...', '?']) {
      expect(filterTranscription({ text }, silence, options).text).toBe('');
    }
  });
});
