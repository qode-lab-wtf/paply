import { describe, expect, it, vi } from 'vitest';
import { createRecordingGeneration } from './recording-generation';
for (const platform of ['mac', 'win']) describe(`Aufnahmegeneration ${platform}`, () => {
  it('stoppt verspäteten Stream nach Stop oder Unmount sofort', () => {
    const generation = createRecordingGeneration(); const token = generation.begin(); generation.cancel();
    const stop = vi.fn(); const stream = { getTracks: () => [{ stop }] } as unknown as MediaStream;
    expect(generation.acceptStream(token, stream)).toBe(false); expect(stop).toHaveBeenCalledOnce();
  });
  it('alter Start darf weder neuen Stream noch neuen Start abbrechen', () => {
    const generation = createRecordingGeneration(); const old = generation.begin(); const current = generation.begin();
    const oldStop = vi.fn(); const newStop = vi.fn();
    generation.acceptStream(old, { getTracks: () => [{ stop: oldStop }] } as unknown as MediaStream);
    expect(generation.acceptStream(current, { getTracks: () => [{ stop: newStop }] } as unknown as MediaStream)).toBe(true);
    expect(oldStop).toHaveBeenCalledOnce(); expect(newStop).not.toHaveBeenCalled();
    expect(generation.isCurrent(old)).toBe(false); expect(generation.isCurrent(current)).toBe(true);
  });
});
