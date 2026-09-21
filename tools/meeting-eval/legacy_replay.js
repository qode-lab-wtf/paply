// Diagnostic only: replays the installed temporal deletion rule on candidate ASR.
// The inputs are not human-reviewed truth and this does not measure speech loss.
const fs = require('node:fs');
const { suppressBleed } = require('../../electron-menubar/meeting/transcript-merger');
const [micPath, systemPath] = process.argv.slice(2);
if (!micPath || !systemPath) throw new Error('Usage: node legacy_replay.js MIC_WHISPER_JSON SYSTEM_WHISPER_JSON');
function load(path) {
  const result = JSON.parse(fs.readFileSync(path, 'utf8'));
  if (result.status !== 'completed' || result.candidate !== 'whisper') throw new Error('Expected completed Whisper result');
  return result.segments.map(s => ({ tStart: s.start, tEnd: s.end }));
}
const mic = load(micPath), system = load(systemPath);
const retained = new Set(suppressBleed(mic, system));
const suppressed = mic.filter(s => !retained.has(s));
console.log(JSON.stringify({
  kind: 'diagnostic_replay_not_reference',
  micSegments: mic.length, systemSegments: system.length,
  retainedMicSegments: retained.size, suppressedMicSegments: suppressed.length,
  suppressedMicSegmentSeconds: suppressed.reduce((sum,s) => sum + s.tEnd - s.tStart, 0),
  accuracyVerified: false,
  caveat: 'Candidate ASR intervals only. Suppression does not prove genuine speech loss; echo versus independent speech needs audio review.'
}, null, 2));
