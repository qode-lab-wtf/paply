import type { ElectronAPI, Settings } from '@/types/electron';

/** IPC failures are resolved values as well as rejected promises. */
export async function saveSettings(api: Pick<ElectronAPI, 'setSettings'>, updates: Partial<Settings>): Promise<void> {
  const result = await api.setSettings(updates);
  if (result !== true) throw new Error(result.error.message);
}
