import { useEffect, useState } from 'react';
import {
  ArrowRight,
  Check,
  ExternalLink,
  Keyboard,
  KeyRound,
  Loader2,
  Mic,
  Sparkles,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { formatShortcut } from '@/lib/shortcut';
import { cn } from '@/lib/utils';
import type { Settings, MicrophonePermission } from '@/types/electron';

const steps = ['Willkommen', 'Schlüssel', 'Mikrofon', 'Tastenkürzel', 'Fertig'];
const icons = [Sparkles, KeyRound, Mic, Keyboard, Check];

export function Onboarding({
  settings,
  isMac,
  onDone,
}: {
  settings: Settings;
  isMac: boolean;
  onDone: () => void;
}) {
  const [step, setStep] = useState(0);
  const [key, setKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [keySaved, setKeySaved] = useState(!!settings.groqApiKey);
  const [feedback, setFeedback] = useState('');
  const [canOverride, setCanOverride] = useState(false);
  const [permission, setPermission] = useState<MicrophonePermission | null>(null);
  const [error, setError] = useState('');
  const Icon = icons[step];

  const checkMicrophone = async (request = false) => {
    setBusy(true);
    setError('');
    try {
      let result = await window.electronAPI.microphonePermission(request);
      // Windows hat keinen askForMediaAccess-Dialog. getUserMedia fordert ihn an
      // und gibt das Mikrofon sofort wieder frei; Aufnahme/Diktat bleiben separat.
      if (!isMac && request && result.status !== 'denied' && result.status !== 'restricted') {
        try {
          const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
          stream.getTracks().forEach((track) => track.stop());
          result = await window.electronAPI.microphonePermission();
          result = { ...result, status: 'granted' };
        } catch (cause) {
          result = {
            ...result,
            status:
              cause instanceof DOMException && cause.name === 'NotAllowedError'
                ? 'denied'
                : 'unavailable',
          };
        }
      }
      setPermission(result);
    } catch {
      setError('Die Berechtigung konnte nicht geprüft werden. Versuch es noch einmal.');
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    if (step === 2) void checkMicrophone();
  }, [step]);

  const validate = async (saveAnyway = false) => {
    setBusy(true);
    setError('');
    setFeedback('');
    setCanOverride(false);
    try {
      const result = await window.electronAPI.validateGroqKey(key, saveAnyway);
      setKeySaved(result.saved || keySaved);
      setCanOverride(!result.saved);
      setFeedback(
        result.saved
          ? result.status === 'valid'
            ? 'Dein Schlüssel ist gültig und gespeichert.'
            : 'Dein Schlüssel ist auf deinen Wunsch gespeichert. Die Prüfung war nicht erfolgreich.'
          : result.status === 'invalid'
            ? 'Dieser Schlüssel ist ungültig. Prüfe ihn bitte noch einmal.'
            : 'Keine Verbindung zu Groq. Bitte versuch es später noch einmal.'
      );
      if (result.saved) setKey('');
    } catch {
      setError('Die Prüfung ist gerade nicht möglich. Versuch es noch einmal.');
    } finally {
      setBusy(false);
    }
  };

  const finish = async () => {
    setBusy(true);
    setError('');
    try {
      await window.electronAPI.completeOnboarding();
      onDone();
    } catch {
      setError('Der Abschluss konnte nicht gespeichert werden. Versuch es noch einmal.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="min-h-screen bg-background text-foreground flex flex-col items-center justify-center px-8 py-10">
      <div className="w-full max-w-2xl space-y-8">
        <div className="flex items-center justify-between">
          <span className="text-lg font-semibold tracking-tight">paply</span>
          <span className="text-sm text-muted-foreground">Dein Start · {step + 1} von 5</span>
        </div>
        <nav aria-label="Fortschritt der Ersteinrichtung" className="grid grid-cols-5 gap-3">
          {steps.map((label, index) => (
            <button
              key={label}
              disabled={busy}
              aria-current={step === index ? 'step' : undefined}
              onClick={() => {
                setStep(index);
                setError('');
              }}
              className="space-y-2 text-left group"
            >
              <span
                className={cn('block h-1 rounded-full', index <= step ? 'bg-primary' : 'bg-muted')}
              />
              <span
                className={cn(
                  'text-xs',
                  index === step ? 'text-foreground font-medium' : 'text-muted-foreground'
                )}
              >
                {label}
              </span>
            </button>
          ))}
        </nav>
        <Card className="shadow-sm">
          <CardContent className="p-10 min-h-[390px] flex flex-col justify-center gap-6">
            <div className="w-12 h-12 rounded-xl bg-muted flex items-center justify-center">
              <Icon className="w-6 h-6 text-primary" />
            </div>
            {step === 0 && (
              <div className="space-y-4">
                <h1 className="text-3xl font-semibold tracking-tight">
                  Sag es. Paply schreibt es.
                </h1>
                <p className="text-muted-foreground leading-relaxed text-lg">
                  Paply verwandelt deine Stimme in Text und fügt ihn direkt dort ein, wo du gerade
                  arbeitest.
                </p>
                <p className="text-sm text-muted-foreground">
                  In wenigen Schritten bist du bereit. Du kannst jeden Schritt überspringen und
                  später zurückkommen.
                </p>
              </div>
            )}
            {step === 1 && (
              <div className="space-y-5">
                <div className="space-y-3">
                  <h1 className="text-2xl font-semibold tracking-tight">
                    Dein Schlüssel zur Stimme
                  </h1>
                  <p className="text-muted-foreground leading-relaxed">
                    Groq wandelt deine Aufnahme in Text um und erhält dafür dein Audio. Erstelle
                    dort einen kostenlosen API-Schlüssel und füge ihn hier ein; es gelten die
                    Nutzungslimits von Groq.
                  </p>
                </div>
                <Button
                  variant="outline"
                  onClick={() =>
                    window.electronAPI
                      .openGroqKeys()
                      .catch(() =>
                        setError(
                          'Der Browser konnte nicht geöffnet werden. Öffne console.groq.com/keys.'
                        )
                      )
                  }
                >
                  Kostenlosen Schlüssel holen <ExternalLink className="w-4 h-4" />
                </Button>
                <div className="space-y-2">
                  <Label htmlFor="onboarding-groq">Groq API-Schlüssel</Label>
                  <div className="flex gap-2">
                    <Input
                      id="onboarding-groq"
                      type="password"
                      autoComplete="off"
                      spellCheck={false}
                      value={key}
                      disabled={busy}
                      onChange={(event) => {
                        setKey(event.target.value);
                        setFeedback('');
                        setCanOverride(false);
                      }}
                      placeholder={keySaved ? 'Ein Schlüssel ist bereits gespeichert' : 'gsk_…'}
                    />
                    <Button disabled={busy || !key.trim()} onClick={() => validate()}>
                      {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Prüfen'}
                    </Button>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Der Schlüssel bleibt in deinen lokalen App-Einstellungen.
                  </p>
                </div>
                {feedback && (
                  <p role="status" className="text-sm">
                    {feedback}
                  </p>
                )}
                {canOverride && (
                  <Button
                    variant="link"
                    className="px-0"
                    disabled={busy || !key.trim()}
                    onClick={() => validate(true)}
                  >
                    Trotzdem speichern
                  </Button>
                )}
              </div>
            )}
            {step === 2 && (
              <div className="space-y-4">
                <h1 className="text-2xl font-semibold tracking-tight">Deine Stimme darf rein</h1>
                <p className="text-muted-foreground">
                  Erlaube Paply den Zugriff auf dein Mikrofon, damit du diktieren kannst.
                </p>
                <p role="status" className="text-sm">
                  {permission?.status === 'granted'
                    ? '✓ Mikrofon ist freigegeben.'
                    : permission?.status === 'denied' || permission?.status === 'restricted'
                      ? isMac
                        ? 'Der Mikrofonzugriff ist gesperrt. Erlaube Paply den Zugriff in den Systemeinstellungen.'
                        : 'Öffne Einstellungen → Datenschutz & Sicherheit → Mikrofon. Aktiviere den Mikrofonzugriff und „Desktop-Apps den Zugriff auf das Mikrofon erlauben“.'
                      : permission?.status === 'unavailable'
                        ? 'Kein Mikrofon erreichbar. Prüfe, ob es angeschlossen und verfügbar ist.'
                        : 'Prüfe jetzt deinen Mikrofonzugriff.'}
                </p>
                <div className="flex flex-wrap gap-2">
                  <Button disabled={busy} onClick={() => checkMicrophone(true)}>
                    {busy ? 'Wird geprüft …' : 'Mikrofon prüfen & freigeben'}
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() =>
                      window.electronAPI
                        .openMicrophoneSettings()
                        .catch(() =>
                          setError('Die Systemeinstellungen konnten nicht geöffnet werden.')
                        )
                    }
                  >
                    Mikrofon-Einstellungen
                  </Button>
                </div>
                {isMac && (
                  <div className="border-t pt-4 space-y-3">
                    <p className="text-sm text-muted-foreground">
                      {permission?.accessibilityGranted
                        ? '✓ Bedienungshilfen sind freigegeben.'
                        : 'Zum automatischen Einfügen braucht Paply zusätzlich die Berechtigung „Bedienungshilfen“. Aktiviere Paply dort und prüfe danach erneut.'}
                    </p>
                    <Button
                      variant="link"
                      className="px-0"
                      onClick={() => window.electronAPI.openAccessibilitySettings()}
                    >
                      Bedienungshilfen öffnen
                    </Button>
                  </div>
                )}
              </div>
            )}
            {step === 3 && (
              <div className="space-y-5">
                <h1 className="text-2xl font-semibold tracking-tight">Ein Kürzel. Deine Worte.</h1>
                <kbd className="inline-block rounded-xl border bg-muted px-6 py-4 text-3xl font-medium tracking-wide">
                  {formatShortcut(settings.shortcut, isMac)}
                </kbd>
                <p className="text-muted-foreground leading-relaxed">
                  Ausprobieren: Kürzel drücken, etwas sagen, nochmal drücken. Das Kürzel kannst du
                  jederzeit in den Einstellungen ändern.
                </p>
                {!keySaved && (
                  <p className="text-sm text-muted-foreground">
                    Zum Ausprobieren brauchst du zuerst einen Groq-Schlüssel.
                  </p>
                )}
                <Label htmlFor="onboarding-try" className="block text-sm">
                  Klicke hier hinein und probiere es aus
                </Label>
                <Textarea
                  id="onboarding-try"
                  placeholder="Hier erscheint dein diktierter Text …"
                  className="resize-none"
                />
              </div>
            )}
            {step === 4 && (
              <div className="space-y-4">
                <h1 className="text-3xl font-semibold tracking-tight">Bereit, wenn du es bist.</h1>
                <p className="text-lg text-muted-foreground leading-relaxed">
                  {isMac
                    ? 'Paply wohnt jetzt in deiner Menüleiste. Über das Symbol kommst du jederzeit zurück.'
                    : 'Paply wohnt jetzt im Tray neben der Uhr. Über den Pfeil ^ findest du auch ausgeblendete Symbole.'}
                </p>
                {!keySaved && (
                  <p className="text-sm text-muted-foreground">
                    Dein Groq-Schlüssel fehlt noch. Ohne ihn kannst du noch nicht diktieren. Beim
                    nächsten Start erinnern wir dich daran.
                  </p>
                )}
              </div>
            )}
            {error && (
              <p role="alert" className="text-sm text-destructive">
                {error}
              </p>
            )}
          </CardContent>
        </Card>
        <div className="flex justify-between items-center">
          <Button variant="ghost" disabled={busy || step === 0} onClick={() => setStep(step - 1)}>
            Zurück
          </Button>
          <div className="flex items-center gap-3">
            {step < 4 && (
              <Button variant="ghost" disabled={busy} onClick={() => setStep(step + 1)}>
                Überspringen
              </Button>
            )}
            <Button
              size="lg"
              disabled={busy}
              onClick={() => (step === 4 ? finish() : setStep(step + 1))}
            >
              {step === 4 ? 'Paply öffnen' : step === 0 ? 'Los geht’s' : 'Weiter'}
              <ArrowRight className="w-4 h-4" />
            </Button>
          </div>
        </div>
      </div>
    </main>
  );
}
