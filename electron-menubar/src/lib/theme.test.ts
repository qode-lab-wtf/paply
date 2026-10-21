import { it, expect, vi } from 'vitest';
import { followSystemTheme } from './theme';

it('übernimmt den Systemmodus und räumt die Änderungsbeobachtung auf', () => {
  let listener: () => void = () => {};
  const media = { matches: true, addEventListener: vi.fn((_event, cb) => { listener = cb; }), removeEventListener: vi.fn() };
  const root = { classList: { toggle: vi.fn() } };
  const cleanup = followSystemTheme(media as unknown as MediaQueryList, root as unknown as HTMLElement);
  expect(root.classList.toggle).toHaveBeenCalledWith('dark', true);
  media.matches = false; listener();
  expect(root.classList.toggle).toHaveBeenLastCalledWith('dark', false);
  cleanup();
  expect(media.removeEventListener).toHaveBeenCalledWith('change', listener);
});
