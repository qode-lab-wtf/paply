import { useEffect, useId, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

export function CustomVocabularySettings({ value, onSave }: {
  value: string;
  onSave: (value: string) => Promise<unknown>;
}) {
  const id = useId();
  const [draft, setDraft] = useState(value);
  const [saving, setSaving] = useState(false);
  useEffect(() => setDraft(value), [value]);
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>Eigene Begriffe (optional)</Label>
      <p id={`${id}-description`} className="text-xs text-muted-foreground">
        Namen und Fachwörter, die oft falsch erkannt werden, durch Komma getrennt
      </p>
      <Textarea id={id} aria-describedby={`${id}-description`} value={draft}
        onChange={event => setDraft(event.target.value)} rows={3} />
      <Button size="sm" disabled={saving || draft === value} onClick={async () => {
        setSaving(true);
        try { await onSave(draft); } finally { setSaving(false); }
      }}>Speichern</Button>
    </div>
  );
}
