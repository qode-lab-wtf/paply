import { buildPrompt, primer, estimateTokens } from '../dictation/whisper-prompt';
import { afterEach, describe, expect, it, vi } from 'vitest';
import vm from 'node:vm';
import { makeMain, source, speech } from './helpers/dictation-main';
import { createPolishClient } from '../dictation/polish-client';
import { getCustomAgentPrompt } from '../dictation/custom-agent-prompt';
import { POLISH_MODEL, POLISH_FALLBACK_MODEL } from '../dictation/groq-models';

const fixtures = [];
function main(platform, settings = {}) {
  const fixture = makeMain(platform, settings); fixtures.push(fixture);
  const c = fixture.context;
  c.getCustomAgentPrompt = getCustomAgentPrompt;
  c.runPolish = createPolishClient({ request: c.readResponse });
  vm.runInContext(source.slice(source.indexOf('async function polishText('), source.indexOf('// WINDOWS\n')), c);
  return fixture;
}
const response = data => ({ ok: true, status: 200, text: async () => JSON.stringify(data) });
const raw = 'Morgen arbeiten wir gemeinsam an diesen offenen Aufgaben.';
const polished = 'Morgen arbeiten wir gemeinsam an diesen offenen Aufgaben!';
const segment = { start: 0, end: 2, text: raw, avg_logprob: -0.7 };

afterEach(() => { for (const fixture of fixtures.splice(0)) fixture.dispose(); });

describe.each(['darwin', 'win32'])('P2 im echten Diktatpfad auf %s', platform => {
  it.each(['coding', 'dictation', 'meeting'])('poliert Profil %s mit Rohkontext, Unsicherheit und Wortliste', async activeProfile => {
    const { context: c } = main(platform, {
      activeProfile, profiles: { [activeProfile]: { polishFlavor: activeProfile === 'coding' ? 'code' : activeProfile === 'dictation' ? 'plain' : 'meeting' } },
      customVocabulary: 'Paply, Müller',
      history: [{ timestamp: new Date(Date.now() - 60000).toISOString(), transcript: 'Vorheriges Rohdiktat', polished: 'Fremde Politur' }],
    });
    c.fetch.mockResolvedValueOnce(response({ text: raw, segments: [segment] }))
      .mockResolvedValueOnce(response({ data: [{ id: POLISH_MODEL }] }))
      .mockResolvedValueOnce(response({ choices: [{ finish_reason: 'stop', message: { content: polished } }] }));
    const result = await c.processAudioData(Buffer.from('audio'), false, speech);
    expect(result.polished).toBe(polished);
    expect(c.autopasteText).toHaveBeenCalledWith(polished, null);
    expect(c.fetch.mock.calls[0][1].body.get('prompt')).toBe(buildPrompt('Paply, Müller', '', primer(['de', 'en'])));
    const payload = JSON.parse(c.fetch.mock.calls[2][1].body);
    expect(payload.model).toBe(POLISH_MODEL); expect(payload.temperature).toBe(0);
    expect(JSON.parse(payload.messages[1].content)).toEqual({
      current_dictation: raw, background_do_not_edit: ['Vorheriges Rohdiktat'],
      uncertain_segments: [segment], custom_terms: 'Paply, Müller',
    });
    expect(c.addToHistory).toHaveBeenCalledWith(expect.objectContaining({ transcript: raw, polished }));
  });
  it('behält bei 404 den Rohtext, warnt einmal und verwendet anschließend das Ausweichmodell', async () => {
    const { context: c } = main(platform);
    const onUnavailable = vi.fn();
    c.runPolish = createPolishClient({ request: c.readResponse, onUnavailable });
    c.fetch.mockResolvedValueOnce(response({ text: raw }))
      .mockResolvedValueOnce(response({ data: [{ id: POLISH_MODEL }, { id: POLISH_FALLBACK_MODEL }] }))
      .mockResolvedValueOnce({ ok: false, status: 404, text: async () => '{}' });
    expect((await c.processAudioData(Buffer.from('audio'), false, speech)).polished).toBeNull();
    expect(c.autopasteText).toHaveBeenCalledWith(raw, null);
    expect(onUnavailable).toHaveBeenCalledOnce();
    c.fetch.mockResolvedValueOnce(response({ text: raw }))
      .mockResolvedValueOnce(response({ choices: [{ finish_reason: 'stop', message: { content: polished } }] }));
    expect((await c.processAudioData(Buffer.from('audio'), false, speech)).polished).toBe(polished);
    expect(JSON.parse(c.fetch.mock.calls[4][1].body).model).toBe(POLISH_FALLBACK_MODEL);
  });
  it('behält bei riskanter Umformulierung den Rohtext', async () => {
    const { context: c } = main(platform);
    c.fetch.mockResolvedValueOnce(response({ text: raw }))
      .mockResolvedValueOnce(response({ data: [{ id: POLISH_MODEL }] }))
      .mockResolvedValueOnce(response({ choices: [{ finish_reason: 'stop', message: { content: 'Heute entscheiden alle Menschen über neue schwierige Projekte.' } }] }));
    expect((await c.processAudioData(Buffer.from('audio'), false, speech)).polished).toBeNull();
    expect(c.autopasteText).toHaveBeenCalledWith(raw, null);
  });
  it('behält den Prompt eigener Agenten unverändert und erlaubt bewusste Erweiterungen', async () => {
    const agent = { id: 'bild', name: 'Bild', template: 'image-prompt' };
    const output = 'Ein ausführlicher Bild-Prompt mit bewusst ergänzter Atmosphäre. '.repeat(3).trim();
    const { context: c } = main(platform, { activeProfile: 'bild', customAgents: [agent], customVocabulary: 'Nicht an eigenen Agenten geben' });
    c.fetch.mockResolvedValueOnce(response({ text: raw }))
      .mockResolvedValueOnce(response({ data: [{ id: POLISH_MODEL }] }))
      .mockResolvedValueOnce(response({ choices: [{ finish_reason: 'stop', message: { content: output } }] }));
    expect((await c.processAudioData(Buffer.from('audio'), false, speech)).polished).toBe(output);
    const payload = JSON.parse(c.fetch.mock.calls[2][1].body);
    expect(payload.messages[1].content).toBe(getCustomAgentPrompt(raw, 'de', agent));
    expect(payload).not.toHaveProperty('temperature');
  });
});

it('erweitert transcribeAudio opt-in und belässt alte Aufrufer bei string', async () => {
  const { context: c } = main('darwin', { customVocabulary: 'ä'.repeat(300) });
  c.fetch.mockResolvedValue(response({ text: raw, segments: [segment,
    { ...segment, text: 'Sicher', avg_logprob: -0.5 },
    { ...segment, text: 'Stille', avg_logprob: -2, no_speech_prob: 0.9 },
  ] }));
  // Der vorhandene Stillefilter bleibt maßgeblich; entfernte Segmente dürfen nicht als Kontext zurückkommen.
  const filteredText = raw + ' Sicher';
  expect(await c.transcribeAudio(Buffer.from('audio'), 'de', 0, speech)).toBe(filteredText);
  expect(await c.transcribeAudio(Buffer.from('audio'), 'de', 0, speech, { returnDetails: true }))
    .toEqual({ text: filteredText, language: null, segments: [segment] });
  expect(estimateTokens(c.fetch.mock.calls[0][1].body.get('prompt'))).toBeLessThanOrEqual(200);
});

it('sendet bei leerer Wortliste nur den Sprachwechsel-Primer', async () => {
  const { context: c } = main('darwin');
  await c.transcribeAudio(Buffer.from('audio'), 'de', 0, speech);
  expect(c.fetch.mock.calls[0][1].body.get('prompt')).toBe(primer(['de', 'en']));
});
