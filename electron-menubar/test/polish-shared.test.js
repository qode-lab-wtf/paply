import { describe, it, expect } from 'vitest';
import cases from '../../shared/polish/safety-cases.json';
import swiftMessages from '../../shared/polish/messages-swift.json';
import { polishRejection, contentWords } from '../dictation/polish';
import { buildPolishMessages, customTermsPrompt } from '../dictation/polish-prompt';
import { digitsPreserved, editDistance } from '../dictation/polish-edit-check';

describe('Gemeinsame mobile Sicherheitsfälle', () => {
  it.each(cases.filter(c => !c.profile || c.profile === 'dictation').map((c, i) => ({ ...c, id: i + 1 })))('$id: $expected — $raw', c => {
    expect(polishRejection(c.raw, c.result, c)).toBe(c.expected);
  });
  it('erzeugt bytegleiches Swift-JSON (JSONEncoder prettyPrinted/sortedKeys/withoutEscapingSlashes)', () => {
    const message = buildPolishMessages('Hallo / Welt\n"Zitat" 😀', {
      history: ['alt', 'eins', '  ', 'zwei', 'drei'], customVocabulary: ' Paply; Müller\nOS11 ',
      segments: [{ text: 'Papli / App', start: 1, end: 2.5, avg_logprob: -0.7 }, { text: 'ohne Zeit', start: null, end: null, avg_logprob: -0.8 }],
    })[1].content;
    expect(Buffer.from(message)).toEqual(Buffer.from(swiftMessages[0]));
    expect(buildPolishMessages('Hallo')[1].content).toBe(swiftMessages[1]);
    expect(customTermsPrompt('a,,; b\r\nc')).toBe('a, b, c');
    expect(buildPolishMessages('Zahlen', { segments: [
      { text: 'klein', start: -0, end: 1e-7, avg_logprob: -1e-5 - 1 },
      { text: 'groß', start: 1e16, end: 1e20, avg_logprob: -0.7 },
    ] })[1].content).toBe(swiftMessages[2]);
  });
  it('behält Ziffern und Reihenfolge, erlaubt Formatierung und Zahlwörter', () => {
    expect(digitsPreserved('Zimmer 12 und 14', 'Zimmer 12 und 41')).toBe(false);
    expect(digitsPreserved('um drei Uhr', 'um 3 Uhr')).toBe(true);
    expect(digitsPreserved('Telefon 0171 123 45 67', 'Telefon 01711234567')).toBe(true);
    expect(editDistance('gepolisht', 'gepolst')).toBe(2);
  });
  it('zählt CJK-Bigramme und Hangul-Silben wie Swift', () => {
    expect(contentWords('会议室')).toEqual(['会议', '议室']);
    expect(contentWords('我用Paply写代码')).toEqual(['我用', 'paply', '写代', '代码']);
    expect(contentWords('내일은 회의에 갈 수 없습니다')).toEqual(['내일은', '회의에', '없습니다']);
  });
});
