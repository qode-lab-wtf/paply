import { useEffect, useState } from 'react';
import { Mic, Key, Keyboard, Volume2, Clipboard, Eye, EyeOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { cn } from '@/lib/utils';
import type { Settings, Platform } from '@/types/electron';

type Tab = 'api' | 'shortcuts' | 'behavior';

export function SettingsApp() {
  const [activeTab, setActiveTab] = useState<Tab>('api');
  const [settings, setSettings] = useState<Settings | null>(null);
  const [platform, setPlatform] = useState<Platform | null>(null);
  const [showGroqKey, setShowGroqKey] = useState(false);
  const [groqKey, setGroqKey] = useState('');
  const [shortcut, setShortcut] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const loadData = async () => {
      try {
        const [settingsData, platformData] = await Promise.all([
          window.electronAPI.getSettings(),
          window.electronAPI.getPlatform(),
        ]);
        setSettings(settingsData);
        setPlatform(platformData);
        setGroqKey(settingsData.groqApiKey || '');
        setShortcut(settingsData.shortcut || '');
      } catch (error) {
        console.error('Failed to load settings:', error);
      }
    };
    loadData();
  }, []);

  const handleSave = async (key: keyof Settings, value: string | boolean) => {
    setIsSaving(true);
    try {
      await window.electronAPI.setSettings({ [key]: value });
      setSettings(prev => prev ? { ...prev, [key]: value } : null);
    } catch (error) {
      console.error('Failed to save setting:', error);
    } finally {
      setIsSaving(false);
    }
  };

  const tabs = [
    { id: 'api' as const, label: 'API Keys', icon: Key },
    { id: 'shortcuts' as const, label: 'Shortcuts', icon: Keyboard },
    { id: 'behavior' as const, label: 'Verhalten', icon: Volume2 },
  ];

  if (!settings) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="animate-pulse text-muted-foreground">Lade...</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background p-5">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <div className="w-9 h-9 rounded-lg bg-primary flex items-center justify-center shadow-sm">
          <Mic className="w-5 h-5 text-primary-foreground" />
        </div>
        <h1 className="text-lg font-semibold">Einstellungen</h1>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 p-1 mb-6 bg-muted rounded-lg">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={cn(
              'flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-md text-sm font-medium transition-colors',
              activeTab === tab.id
                ? 'bg-primary text-primary-foreground'
                : 'text-muted-foreground hover:text-foreground hover:bg-background'
            )}
          >
            <tab.icon className="w-4 h-4" />
            {tab.label}
          </button>
        ))}
      </div>

      {/* Content */}
      {activeTab === 'api' && (
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Groq API Key</CardTitle>
              <CardDescription>
                Für Whisper-Transkription & Text-Polishing. Hol dir einen Key auf{' '}
                <a
                  href="https://console.groq.com/keys"
                  className="text-primary underline"
                  target="_blank"
                  rel="noopener"
                >
                  console.groq.com
                </a>
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex gap-2">
                <div className="relative flex-1">
                  <Input
                    type={showGroqKey ? 'text' : 'password'}
                    value={groqKey}
                    onChange={(e) => setGroqKey(e.target.value)}
                    placeholder="gsk_..."
                    className="pr-10"
                  />
                  <button
                    type="button"
                    onClick={() => setShowGroqKey(!showGroqKey)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                  >
                    {showGroqKey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
                <Button
                  onClick={() => handleSave('groqApiKey', groqKey)}
                  disabled={isSaving}
                >
                  Speichern
                </Button>
              </div>
            </CardContent>
          </Card>

        </div>
      )}

      {activeTab === 'shortcuts' && (
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Aufnahme-Shortcut</CardTitle>
              <CardDescription>
                Globaler Hotkey zum Starten/Stoppen der Aufnahme
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex gap-2">
                <Input
                  value={shortcut}
                  onChange={(e) => setShortcut(e.target.value)}
                  placeholder={platform?.isMac ? 'Alt+Command+K' : 'Ctrl+Alt+K'}
                />
                <Button
                  onClick={() => handleSave('shortcut', shortcut)}
                  disabled={isSaving}
                >
                  Speichern
                </Button>
              </div>
              <p className="mt-2 text-xs text-muted-foreground">
                Beispiele: {platform?.isMac ? 'Command+Shift+R, Alt+Command+K' : 'Ctrl+Shift+R, Ctrl+Alt+K'}
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Weitere Shortcuts</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Smart-Paste</span>
                  <kbd className="px-2 py-1 rounded bg-muted text-xs font-mono">
                    {platform?.isMac ? '⌘⇧V' : 'Ctrl+Shift+V'}
                  </kbd>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Letzte Aufnahme wiederholen</span>
                  <kbd className="px-2 py-1 rounded bg-muted text-xs font-mono">
                    {platform?.isMac ? '⌘⇧R' : 'Ctrl+Shift+R'}
                  </kbd>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Screen-Parser</span>
                  <kbd className="px-2 py-1 rounded bg-muted text-xs font-mono">
                    {platform?.isMac ? '⌘⇧S' : 'Ctrl+Shift+S'}
                  </kbd>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {activeTab === 'behavior' && (
        <div className="space-y-4">
          <Card>
            <CardContent className="p-4 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <Label>Autopaste</Label>
                  <p className="text-xs text-muted-foreground">
                    Text automatisch in aktive App einfügen
                  </p>
                </div>
                <Switch
                  checked={settings.autopaste}
                  onCheckedChange={(checked) => handleSave('autopaste', checked)}
                />
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <Label>In Zwischenablage kopieren</Label>
                  <p className="text-xs text-muted-foreground">
                    Zusätzlich in Clipboard kopieren
                  </p>
                </div>
                <Switch
                  checked={settings.copyToClipboard}
                  onCheckedChange={(checked) => handleSave('copyToClipboard', checked)}
                />
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <Label>Polish aktivieren</Label>
                  <p className="text-xs text-muted-foreground">
                    Text mit Groq Llama optimieren
                  </p>
                </div>
                <Switch
                  checked={settings.enablePolish}
                  onCheckedChange={(checked) => handleSave('enablePolish', checked)}
                />
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <Label>Beep-Sound</Label>
                  <p className="text-xs text-muted-foreground">
                    Audio-Feedback bei Aufnahme
                  </p>
                </div>
                <Switch
                  checked={settings.beepEnabled}
                  onCheckedChange={(checked) => handleSave('beepEnabled', checked)}
                />
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <Label>Autostart</Label>
                  <p className="text-xs text-muted-foreground">
                    Beim Systemstart automatisch öffnen
                  </p>
                </div>
                <Switch
                  checked={settings.autoStart}
                  onCheckedChange={(checked) => handleSave('autoStart', checked)}
                />
              </div>

              {platform?.isMac && (
                <div className="flex items-center justify-between">
                  <div>
                    <Label>Dock-Icon verstecken</Label>
                    <p className="text-xs text-muted-foreground">
                      Nur als Menüleisten-App
                    </p>
                  </div>
                  <Switch
                    checked={settings.hideDock}
                    onCheckedChange={(checked) => handleSave('hideDock', checked)}
                  />
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Sprache</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex gap-2">
                <Button
                  variant={settings.language === 'de' ? 'default' : 'outline'}
                  className="flex-1"
                  onClick={() => handleSave('language', 'de')}
                >
                  🇩🇪 Deutsch
                </Button>
                <Button
                  variant={settings.language === 'en' ? 'default' : 'outline'}
                  className="flex-1"
                  onClick={() => handleSave('language', 'en')}
                >
                  🇬🇧 English
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}

