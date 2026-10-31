import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import {
  needsCheck,
  decide,
  confidence,
  guardedTranscription,
  userLanguages,
} from '../dictation/language-guard';
import {
  primer,
  buildPrompt,
  estimateTokens,
  removeEchoes,
} from '../dictation/whisper-prompt';
import { makeMain, speech } from './helpers/dictation-main';
const cases = JSON.parse(
  fs.readFileSync(new URL('../../shared/sprache/faelle.json', import.meta.url)),
);
describe('Gemeinsame Sprachfälle', () => {
  for (const c of cases)
    it(c.name, () => {
      expect(needsCheck(c)).toBe(c.check);
      expect(c.check ? decide(c) : 'detected').toBe(c.result);
    });
});
it('Konfidenz gewichtet rohe Segmente nach Dauer, auch Null-Dauer', () => {
  expect(
    confidence({
      segments: [
        { start: 0, end: 1, avg_logprob: -0.1 },
        { start: 1, end: 4, avg_logprob: -0.5 },
      ],
    }),
  ).toBeCloseTo(-0.4);
  expect(
    confidence({ segments: [{ start: 0, end: 0, avg_logprob: -0.3 }] }),
  ).toBeCloseTo(-0.3);
  expect(confidence({ segments: [{}] })).toBe(null);
});
it('Basis-Sprachen und englische Ergänzung', () => {
  expect(userLanguages('de', ['de-DE'])).toEqual(['de', 'en']);
  expect(userLanguages('fr', ['en-US', 'de-DE'])).toEqual(['fr', 'en', 'de']);
});
for (const scenario of ['fr', 'de', 'failed'])
  it(`Echter Main-Ablauf: ${scenario}`, async () => {
    const m = makeMain('darwin', { autopaste: false, copyToClipboard: false });
    const answer = (text, language, lp) => ({
      ok: true,
      text: async () =>
        JSON.stringify({
          text,
          language,
          duration: 2,
          segments: [{ text, start: 0, end: 2, avg_logprob: lp }],
        }),
    });
    m.context.fetch
      .mockReset()
      .mockResolvedValueOnce(
        answer(
          scenario === 'de'
            ? 'Wir sehen uns heute Abend.'
            : 'On se voit ce soir.',
          scenario === 'de' ? 'German' : 'French',
          -0.08,
        ),
      );
    if (scenario === 'failed')
      m.context.fetch.mockRejectedValueOnce(new Error('network'));
    else
      m.context.fetch.mockResolvedValueOnce(
        answer('Wir sehen uns heute Abend.', 'German', -0.39),
      );
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, speech);
      expect(m.context.fetch).toHaveBeenCalledTimes(scenario === 'de' ? 1 : 2);
      expect(m.context.fetch.mock.calls[0][1].body.has('language')).toBe(false);
      if (scenario !== 'de')
        expect(m.context.fetch.mock.calls[1][1].body.get('language')).toBe(
          'de',
        );
      expect(m.context.addToHistory).toHaveBeenCalledWith(
        expect.objectContaining({
          language: scenario === 'de' ? 'de' : 'fr',
          transcript:
            scenario === 'de'
              ? 'Wir sehen uns heute Abend.'
              : 'On se voit ce soir.',
        }),
      );
    } finally {
      m.dispose();
    }
  });
it('gleicher normalisierter Text gewinnt vor fehlender Konfidenz', async () => {
  let calls = 0;
  const out = await guardedTranscription(
    async () =>
      ++calls === 1
        ? { text: ' Hello! ', language: 'English' }
        : { text: 'hello', language: 'German' },
    { expected: 'de', users: ['de', 'en'], spoken: 1 },
  );
  expect(out.language).toBe('de');
});
it('Primer, Tokenbudget und konservative Echoentfernung', () => {
  expect(primer(['de'])).toBe('');
  expect(primer(['de', 'ar'])).toBe('');
  const example = primer(['de', 'en']);
  expect(example).toContain('and the new date');
  expect(
    estimateTokens(
      buildPrompt('Wort, '.repeat(100), 'alter Kontext '.repeat(100), example),
    ),
  ).toBeLessThanOrEqual(200);
  expect(removeEchoes({ text: example }, { example, speechMs: 0 }).text).toBe(
    '',
  );
  expect(
    removeEchoes({ text: example }, { example, speechMs: 10000 }).text,
  ).toBe(example);
});

it('Notes verwendet Entwickler-Modell, Vorstücksprache und zwei echte Multipart-Anfragen', async () => {
 const { createGroq } = await import('../notes/groq');
 const calls=[];
 const ledger={reserve:()=>1,settle:()=>{}};
 const groq=createGroq({getKey:()=> 'test',ledger,getTranscriptionSettings:()=>({language:'de',whisperModel:'whisper-large-v3-turbo',systemLanguages:['de-DE']}),fetchImpl:async(_url,{body})=>{
  calls.push(body); const check=body.has('language');
  return {ok:true,json:async()=>({text:check?'On se voit ce soir.':'Wir sehen uns heute Abend.',language:check?'French':'German',segments:[{start:0,end:2,avg_logprob:check?-.2:-.6}]})};
 }});
 const out=await groq.transcribe(Buffer.alloc(64),2,undefined,'',{previousLanguage:'fr',previousText:'Bonjour.',voiceActivity:{speechMs:1000}});
 expect(calls).toHaveLength(2); expect(calls[0].has('language')).toBe(false);
 expect(calls[1].get('language')).toBe('fr');
 expect(calls[0].get('model')).toBe('whisper-large-v3-turbo');
 expect(calls[0].get('prompt')).toContain('Bonjour.'); expect(out.language).toBe('fr');
});

it('Meeting-Fallback führt Gegenprobe aus und merkt Sprache je Kanal', async () => {
 const { TranscriptionQueue }=await import('../meeting/transcription-queue');
 const calls=[];
 const q=new TranscriptionQueue({apiKey:'test',language:'de',fetchImpl:async(_url,{body})=>{
  calls.push(body); const forced=body.get('language');
  const text=forced?'Wir sehen uns heute Abend.':'On se voit ce soir.';
  return {ok:true,json:async()=>({text,language:forced?'German':'French',segments:[{text,start:0,end:2,avg_logprob:forced?-.6:-.1}]})};
 }});
 q.enqueue({channel:'mic',wavBuffer:Buffer.alloc(64044),tOffset:0});
 q.enqueue({channel:'mic',wavBuffer:Buffer.alloc(64044),tOffset:2});
 q.enqueue({channel:'system',wavBuffer:Buffer.alloc(64044),tOffset:0});
 await q.idle(); expect(calls).toHaveLength(5);
 expect(calls.map(c=>c.get('language'))).toEqual([null,'de',null,null,'de']);
});
