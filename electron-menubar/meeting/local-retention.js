'use strict';
// Only schema-v2 recordings explicitly enrolled at creation. Never retroactively enroll history.
const fs = require('node:fs');
const path = require('node:path');
const { readJson, atomicJson } = require('./local-files');
function cleanExpiredAudio(baseDir, now = Date.now()) {
  const cleaned = [];
  if (!fs.existsSync(baseDir)) return cleaned;
  for (const entry of fs.readdirSync(baseDir, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.isSymbolicLink()) continue;
    const dir = path.join(baseDir, entry.name), statePath = path.join(dir, 'local-state.json');
    let state; try { state = readJson(statePath); } catch { continue; }
    if (state?.schemaVersion !== 2 || state.retentionPolicy !== 'seven-days-from-capture' || !Number.isFinite(state.audioExpiresAt) || now < state.audioExpiresAt) continue;
    // Retention wins even over failed processing. No symlinks are followed.
    const removeAudio = (folder) => {
      for (const file of fs.readdirSync(folder, { withFileTypes: true })) {
        const p = path.join(folder, file.name);
        if (file.isSymbolicLink()) continue;
        if (file.isDirectory()) removeAudio(p);
        else if (/\.(wav|pcm|opus|flac|m4a)(\.[\w-]+\.tmp|\.tmp)?$/i.test(file.name)) fs.unlinkSync(p);
      }
    };
    removeAudio(dir);
    const marker = path.join(dir, 'audio-retention.json');
    atomicJson(marker, { audioDeletedAt: readJson(marker)?.audioDeletedAt || now, audioAvailable: false });
    cleaned.push(entry.name);
  }
  return cleaned;
}
if (require.main === module) { cleanExpiredAudio(process.argv[2]); }
module.exports = { cleanExpiredAudio };
