import { describe, expect, it } from 'vitest';
import type { Note } from '@/types/notes';
import { textEdit } from './editor';

const pending = { id: 'raw_s', kind: 'note', owner: 'system', sourceId: 's', text: '', sentenceIds: [], pending: true, rev: 1 } as unknown as Note;
describe('drafts while a transcript arrives', () => {
  it('combines a first draft with the transcript', () => {
    const current = { ...pending, text: 'Gesprochener Gedanke.', sentenceIds: ['s_0'], pending: false, rev: 2 };
    expect(textEdit(pending, current, 'Mein Zusatz')).toEqual({ rev: 2, text: 'Mein Zusatz\n\nGesprochener Gedanke.' });
  });
  it('keeps a reopened draft without duplicating its previously saved prefix', () => {
    const base = { ...pending, owner: 'user' as const, text: 'Idee:', rev: 2 };
    const current = { ...base, text: 'Idee:\n\nGesprochener Gedanke.', sentenceIds: ['s_0'], pending: false, rev: 3 };
    expect(textEdit(base, current, 'Idee: und noch etwas')).toEqual({ rev: 3, text: 'Idee: und noch etwas\n\nGesprochener Gedanke.' });
  });
  it('can save after geometry changes without accepting concurrent text changes', () => {
    const base = { ...pending, text: 'Original', pending: false };
    expect(textEdit(base, { ...base, rev: 2, width: 400 }, 'Entwurf')).toEqual({ rev: 2, text: 'Entwurf' });
    expect(textEdit(base, { ...base, rev: 2, text: 'Anderer Text' }, 'Entwurf')).toEqual({ rev: 1, text: 'Entwurf' });
  });
});
