import { describe, it, expect } from 'vitest';
import { normalizeSummary, summaryToMarkdown, formatTime } from './meeting-summary';

describe('normalizeSummary', () => {
  it('bildet v1 auf v2 ab (Kernpunkte → ein Thema, Titel aus Kurzzusammenfassung)', () => {
    const v2 = normalizeSummary({
      kurzzusammenfassung: 'Wir haben über das Budget gesprochen.',
      kernpunkte: ['Budget 5000 €', 'Start im Oktober'],
      todos: [{ text: 'Angebot einholen', verantwortlich: 'Sprecher 2', erledigt: true }],
      offeneFragen: ['Wer zahlt?'],
      generatedAt: 'x', model: 'm',
    } as never);
    expect(v2).not.toBeNull();
    expect(v2!.schema).toBe(2);
    expect(v2!.titel).toBe('Wir haben über das Budget gesprochen.');
    expect(v2!.themen).toEqual([{ ueberschrift: 'Kernpunkte', inhalt: '• Budget 5000 €\n• Start im Oktober' }]);
    expect(v2!.todos[0]).toEqual({ text: 'Angebot einholen', verantwortlich: 'Sprecher 2', frist: null, erledigt: true });
    expect(v2!.offeneFragen).toEqual(['Wer zahlt?']);
    expect(v2!.entscheidungen).toEqual([]);
  });

  it('lässt v2 unverändert durch und füllt Defaults', () => {
    const v2 = normalizeSummary({ schema: 2, titel: 'T', kurzfassung: 'K', themen: [{ ueberschrift: 'A', inhalt: 'B' }], entscheidungen: [{ text: 'E' }], offeneFragen: [], todos: [{ text: 'X' }] } as never);
    expect(v2!.titel).toBe('T');
    expect(v2!.entscheidungen).toEqual([{ text: 'E', begruendung: '' }]);
    expect(v2!.todos).toEqual([{ text: 'X', verantwortlich: null, frist: null, erledigt: false }]);
  });

  it('null bei fehlendem Bericht', () => { expect(normalizeSummary(null)).toBeNull(); });
});

describe('summaryToMarkdown / formatTime', () => {
  it('rendert Bericht und Konversation', () => {
    const md = summaryToMarkdown('Titel', normalizeSummary({ schema: 2, titel: 'Titel', kurzfassung: 'K', themen: [{ ueberschrift: 'A', inhalt: 'B' }], entscheidungen: [], offeneFragen: ['F'], todos: [{ text: 'X', frist: 'Freitag' }] } as never), [{ tStart: 65, speaker: 'Sprecher 1', text: 'Hallo' }]);
    expect(md).toContain('# Titel');
    expect(md).toContain('## A');
    expect(md).toContain('- [ ] X – bis Freitag');
    expect(md).toContain('[01:05] **Sprecher 1:** Hallo');
    expect(formatTime(3725)).toBe('1:02:05');
  });
});
