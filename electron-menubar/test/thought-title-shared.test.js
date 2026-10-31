import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import { validate } from '../notes/thought';
const cases = JSON.parse(fs.readFileSync(new URL('../../shared/gedanken/titel-faelle.json', import.meta.url)));
describe('Gemeinsame Gedanken-Titelfälle', () => {
  for (const c of cases) it(c.name, () => {
    const result = validate({ title: c.title, clean_text: c.transcript, topic: { choice: 'none' }, tasks: [], related: [] },
      { sentences: [{ text: c.transcript }], topics: [], existing: [], spoken_languages: c.spoken, ui_language: c.ui });
    expect(result.title === c.title).toBe(c.ok);
  });
});
