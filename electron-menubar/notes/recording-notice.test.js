import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { it, expect } from 'vitest';
import { RecordingNotice } from '../src/apps/meeting-overlay/RecordingNotice';
it('15: recording notice is visible at start and disappears after fifteen seconds', () => {
  expect(renderToStaticMarkup(React.createElement(RecordingNotice, {durationMs:0}))).toContain('Sag den anderen, dass Paply mitschreibt.');
  expect(renderToStaticMarkup(React.createElement(RecordingNotice, {durationMs:14999}))).toContain('mitschreibt');
  expect(renderToStaticMarkup(React.createElement(RecordingNotice, {durationMs:15000}))).toBe('');
});
