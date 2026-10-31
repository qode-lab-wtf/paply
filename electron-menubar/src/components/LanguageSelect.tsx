import type { Settings } from '../types/electron';
const languages: [Settings['language'], string][] = [
  ['de', 'Deutsch'], ['en', 'English'], ['fr', 'Français'], ['es', 'Español'],
  ['it', 'Italiano'], ['pt', 'Português'], ['nl', 'Nederlands'], ['tr', 'Türkçe'], ['pl', 'Polski'],
];
export function LanguageSelect({ value, onChange }: { value: Settings['language']; onChange: (language: Settings['language']) => void }) {
  return <select aria-label="Hauptsprache" className="h-9 rounded-md border border-input bg-background px-3 text-sm" value={value} onChange={e => onChange(e.target.value as Settings['language'])}>
    {!languages.some(([code]) => code === value) && <option value={value}>{new Intl.DisplayNames(['de'], { type: 'language' }).of(value) || value}</option>}
    {languages.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
  </select>;
}
