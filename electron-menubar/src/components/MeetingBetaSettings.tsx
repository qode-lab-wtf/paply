import { useEffect, useState } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { formatShortcut, keyEventToAccelerator } from '@/lib/shortcut';

export function MeetingBetaSettings({ enabled, isMac }: { enabled: boolean; isMac: boolean }) {
  const [active, setActive] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [retryShortcut, setRetryShortcut] = useState('');
  const change = async (checked: boolean, meetingHotkey?: string) => {
    setSaving(true);
    setError('');
    try {
      await window.electronAPI.setSettings({
        meetingEnabled: checked,
        ...(meetingHotkey ? { meetingHotkey } : {}),
      });
    } catch {
      setError(
        'Umschalten nicht möglich. Beende ein laufendes Meeting oder wähle ein anderes Meeting-Tastenkürzel.'
      );
    } finally {
      setSaving(false);
    }
  };
  useEffect(() => {
    let mounted = true;
    const refresh = () =>
      window.electronAPI
        .getMeetingStatus()
        .then((status) => {
          if (mounted) setActive(status.active);
        })
        .catch(() => {
          /* Im Zweifel bleibt der Schalter gesperrt. */
        });
    refresh();
    // Das separate Einstellungsfenster erhält keine Meeting-Events.
    const timer = setInterval(refresh, 1000);
    return () => {
      mounted = false;
      clearInterval(timer);
    };
  }, []);
  return (
    <Card>
      <CardContent className="pt-6 space-y-2">
        <div className="flex items-center justify-between gap-6">
          <div className="space-y-1">
            <Label htmlFor="meeting-beta">Meeting-Modus (Beta)</Label>
            <p className="text-sm text-muted-foreground">
              Nimm Meetings auf und lass sie auswerten – die Beta ist noch experimentell.
            </p>
          </div>
          <Switch
            id="meeting-beta"
            checked={enabled}
            disabled={active || saving}
            onCheckedChange={(checked) => change(checked)}
          />
        </div>
        {active && (
          <p className="text-xs text-muted-foreground">Beende zuerst das laufende Meeting.</p>
        )}
        {error && (
          <p role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}
        {error && !enabled && !active && (
          <div className="space-y-2 pt-2">
            <Label htmlFor="meeting-retry-hotkey">Neues Meeting-Tastenkürzel</Label>
            <Input
              id="meeting-retry-hotkey"
              readOnly
              value={formatShortcut(retryShortcut, isMac)}
              placeholder="Hier klicken und Tastenkombination drücken"
              onKeyDown={(event) => {
                event.preventDefault();
                const next = keyEventToAccelerator(event.nativeEvent);
                if (next) setRetryShortcut(next);
              }}
            />
            <Button disabled={saving || !retryShortcut} onClick={() => change(true, retryShortcut)}>
              Mit diesem Kürzel einschalten
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
