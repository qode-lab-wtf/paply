'use strict';
const path = require('node:path');
const { atomicJson, readJson, sessionDir } = require('./local-files');
function createLocalStore(baseDir, legacy) {
  const dir = id => sessionDir(baseDir, id);
  const statePath = id => path.join(dir(id), 'local-state.json');
  const readState = id => { const state = readJson(statePath(id)); return state ? { ...state, ...readJson(path.join(dir(id), 'audio-retention.json'), {}) } : null; };
  const writeState = (id, updates) => { const state = { ...readState(id), ...updates }; atomicJson(statePath(id), state); return state; };
  function get(id) {
    dir(id);
    const full = legacy.get(id); if (!full) return null;
    const state = readState(id); if (!state) return full;
    const edits = readJson(path.join(dir(id), 'corrections.json'), { names: {}, segments: {} });
    full.audioOffsets = Object.fromEntries(Object.entries(state.tracks || {}).map(([channel, track]) => [channel, track.offsetSeconds || 0]));
    full.index = { ...full.index, processingStatus: state.status, processingStage: state.stage || null, processingError: state.error || null, captureWarning: state.captureWarning || null, audioExpiresAt: state.audioExpiresAt, schemaVersion: 2, reportNeedsRefresh: !!state.reportNeedsRefresh };
    full.transcript.segments = (full.transcript.segments || []).map(s => {
      const correction = edits.segments[s.id];
      const speakerId = correction?.speakerId || s.speakerId;
      return { ...s, speakerId, text: correction?.text ?? s.text,
        speaker: edits.names[speakerId] || correction?.speaker || s.speaker, corrected: !!correction };
    });
    const identified = new Set(full.transcript.segments.filter(s => s.speakerId && !s.speakerId.endsWith('-unclear')).map(s => s.speaker));
    full.index.diarizationSpeakers = identified.size;
    full.index.speakerCount = identified.size;
    const found = new Set(full.transcript.segments.map(s => s.id));
    const speakerIds = new Set(full.transcript.segments.map(s => s.speakerId));
    full.transcript.unmatchedSpeakerNames = Object.keys(edits.names).filter(id => !speakerIds.has(id));
    full.transcript.unmatchedCorrections = Object.keys(edits.segments).filter(id => !found.has(id));
    return full;
  }
  function saveCorrections(id, update) {
    const p = path.join(dir(id), 'corrections.json');
    const edits = readJson(p, { names: {}, segments: {} }); update(edits); atomicJson(p, edits);
    // Never rewrite generated report text through a global find-and-replace.
    writeState(id, { reportNeedsRefresh: true });
    return true;
  }
  function renameSpeaker(id, from, to) {
    const full = get(id); if (!full || !readState(id)) return legacy.renameSpeaker(id, from, to);
    const matches = full.transcript.segments.filter(s => (s.speaker === from || s.speakerId === from) && s.speakerId && !s.speakerId.endsWith('-unclear'));
    if (!matches.length || typeof to !== 'string' || !to.trim() || to.length > 100) return false;
    return saveCorrections(id, edits => matches.forEach(s => { edits.names[s.speakerId] = to.trim(); }));
  }
  function correctSegment(id, segmentId, patch) {
    const full = get(id), segment = full?.transcript.segments.find(s => s.id === segmentId);
    if (!readState(id) || !segment) return false;
    if (patch.text !== undefined && (typeof patch.text !== 'string' || patch.text.length > 20000)) throw new Error('Ungültiger Text');
    if (patch.speakerId !== undefined && !full.transcript.segments.some(s => s.speakerId === patch.speakerId)) throw new Error('Unbekannter Sprecher');
    return saveCorrections(id, edits => { edits.segments[segmentId] = { ...edits.segments[segmentId], ...(patch.text !== undefined ? {text:patch.text} : {}), ...(patch.speakerId !== undefined ? {speakerId:patch.speakerId} : {}),
      speaker: patch.speakerId ? full.transcript.segments.find(s => s.speakerId === patch.speakerId).speaker : segment.speaker,
      anchor: { channel: segment.channel, tStart: segment.tStart, tEnd: segment.tEnd, originalText: segment.text } }; });
  }
  return { ...legacy, dir, readState, writeState, get, renameSpeaker, correctSegment,
    saveTranscript(id, transcript) { atomicJson(path.join(dir(id), 'transcript.json'), transcript); },
    saveSummary(id, summary) { atomicJson(path.join(dir(id), 'summary.json'), summary); },
    list() { return legacy.list().map(item => { const state = readState(item.id); return state ? { ...item, schemaVersion: 2, processingStatus: state.status } : item; }); },
  };
}
module.exports = { createLocalStore };
