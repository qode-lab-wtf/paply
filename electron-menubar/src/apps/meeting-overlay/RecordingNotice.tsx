import React from 'react';
export function RecordingNotice({ durationMs }: { durationMs: number }) {
  return durationMs < 15000 ? <p className="rounded bg-white px-2 py-1 text-xs text-slate-800">Sag den anderen, dass Paply mitschreibt.</p> : null;
}
