import { buildPrompt, primer } from '../dictation/whisper-prompt';
import { describe, it, expect } from 'vitest';
const { TranscriptionQueue, parseVerbose } = require('./transcription-queue.js');

describe('transcription-queue', () => {
  it('parseVerbose verschiebt Segment-Zeiten um tOffset', () => {
    const json = { segments: [{ start: 0, end: 1.5, text: ' Hallo' }, { start: 1.5, end: 2, text: ' Welt' }] };
    const segs = parseVerbose(json, 30);
    expect(segs).toEqual([{ tStart: 30, tEnd: 31.5, text: 'Hallo' }, { tStart: 31.5, tEnd: 32, text: 'Welt' }]);
  });
  it('enqueue transkribiert und emittiert segments', async () => {
    const fakeFetch = async () => ({ ok: true, json: async () => ({ segments: [{ start: 0, end: 1, text: 'Hi' }] }) });
    const q = new TranscriptionQueue({ apiKey: 'k', language: 'de', fetchImpl: fakeFetch });
    const got = [];
    q.on('segments', (e) => got.push(e));
    q.enqueue({ channel: 'mic', wavBuffer: Buffer.alloc(44), tOffset: 0 });
    await q.idle();
    expect(got[0].channel).toBe('mic');
    expect(got[0].segments[0].text).toBe('Hi');
  });
  it('schickt den Kontext-prompt (getPrompt) als Whisper-prompt mit', async () => {
    let captured = null;
    const fakeFetch = async (_url, opts) => { captured = opts.body; return { ok: true, json: async () => ({ segments: [] }) }; };
    const q = new TranscriptionQueue({
      apiKey: 'k', language: 'de', fetchImpl: fakeFetch,
      getPrompt: (ch) => (ch === 'mic' ? 'voriger gesprochener Text' : ''),
    });
    q.enqueue({ channel: 'mic', wavBuffer: Buffer.alloc(44), tOffset: 0 });
    await q.idle();
    expect(captured.get('prompt')).toBe(buildPrompt('', 'voriger gesprochener Text', ''));
  });
  it('ohne Vorstück und Sprechmessung wird kein Primer gesendet', async () => {
    let captured = null;
    const fakeFetch = async (_url, opts) => { captured = opts.body; return { ok: true, json: async () => ({ segments: [] }) }; };
    const q = new TranscriptionQueue({ apiKey: 'k', language: 'de', fetchImpl: fakeFetch });
    q.enqueue({ channel: 'system', wavBuffer: Buffer.alloc(44), tOffset: 0 });
    await q.idle();
    expect(captured.get('prompt')).toBeNull();
  });
});
it('14: empty pieces do not change expected language',async()=>{
 const q=new TranscriptionQueue({apiKey:'fake',fetchImpl:async()=>({ok:true,json:async()=>({language:'fr',text:'',segments:[]})})});
 q.previousLanguages.mic='de';await q._callGroq({channel:'mic',wavBuffer:Buffer.alloc(44),tOffset:0});expect(q.previousLanguages.mic).toBe('de');
});
it('14: short speech in a long window still gets a language counter-check',async()=>{
 const languages=[];const q=new TranscriptionQueue({apiKey:'fake',language:'de',systemLanguages:['de','fr'],fetchImpl:async(_,opts)=>{languages.push(opts.body.get('language'));return {ok:true,json:async()=>({language:opts.body.get('language')||'fr',text:'Bonjour Sophie',segments:[{start:0,end:1,text:'Bonjour Sophie',avg_logprob:-.2}]})};}});
 const pcm=Buffer.alloc(320000);for(let i=0;i<32000;i+=2)pcm.writeInt16LE(i%4?12000:-12000,i);
 await q._callGroq({channel:'mic',wavBuffer:Buffer.concat([Buffer.alloc(44),pcm]),tOffset:0});expect(languages).toEqual([null,'de']);
});
