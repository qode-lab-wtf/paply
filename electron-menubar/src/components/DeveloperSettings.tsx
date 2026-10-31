import { useEffect, useRef, useState } from 'react';
import type { Settings } from '../types/electron';

/** Gemeinsamer Einstieg für beide echten Einstellungsoberflächen. */
export function DeveloperSettings() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [version, setVersion] = useState('');
  const [clicks, setClicks] = useState(0);
  const count = useRef(0);
  const [error, setError] = useState('');
  useEffect(() => {
    const refresh = () => {
      window.electronAPI.getSettings().then(setSettings);
    };
    refresh();
    window.electronAPI.getPlatform().then((p) => setVersion(p.version || ''));
    return window.electronAPI.onSettingsChanged(refresh);
  }, []);
  async function save(value: Partial<Settings>) {
    try {
      await window.electronAPI.setSettings(value);
      setSettings(await window.electronAPI.getSettings());
      setError('');
    } catch {
      setError('Einstellung konnte nicht gespeichert werden.');
    }
  }
  return (
    <div className="p-4 text-xs space-y-3">
      <button
        type="button"
        onClick={() => {
          if (settings?.developerMode) return;
          count.current += 1;
          setClicks(count.current);
          if (count.current >= 5) {
            void save({ developerMode: true });
            count.current = 0;
            setClicks(0);
          }
        }}
      >
        paply v{version}
      </button>
      {!settings?.developerMode && clicks >= 3 && (
        <p role="status">Noch {5 - clicks}× klicken</p>
      )}
      {settings?.developerMode && (
        <section aria-label="Entwicklerbereich" className="space-y-3">
          <h2 className="font-semibold">Entwicklerbereich</h2>
          <label className="block">
            <input
              type="checkbox"
              checked={settings.enablePolish}
              onChange={(e) => void save({ enablePolish: e.target.checked })}
            />{' '}
            Polieren
          </label>
          <label className="block">
            Whisper-Modell{' '}
            <select
              className="bg-background border rounded max-w-full"
              value={settings.whisperModel}
              onChange={(e) =>
                void save({
                  whisperModel: e.target.value as Settings['whisperModel'],
                })
              }
            >
              <option value="whisper-large-v3">whisper-large-v3</option>
              <option value="whisper-large-v3-turbo">
                whisper-large-v3-turbo
              </option>
            </select>
          </label>
          <button
            className="block underline"
            onClick={() => void window.electronAPI.showDiagnosticLog()}
          >
            Protokoll anzeigen
          </button>
          <button
            className="block underline"
            onClick={() => void save({ developerMode: false })}
          >
            Entwicklerbereich ausblenden
          </button>
        </section>
      )}
      {error && <p role="alert">{error}</p>}
    </div>
  );
}
