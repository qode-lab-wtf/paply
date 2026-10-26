'use strict';
const path = require('node:path');
const { execFileSync } = require('node:child_process');
function readKeyLabels({ platform = process.platform, resourcesPath = process.resourcesPath, run = execFileSync } = {}) {
  if (platform !== 'darwin') return {};
  const binary = resourcesPath?.endsWith('/Contents/Resources') && !resourcesPath.includes('/node_modules/electron/')
    ? path.join(resourcesPath, 'bin', 'macos-notes-keymap')
    : path.join(__dirname, '..', 'resources', 'bin', 'macos-notes-keymap');
  try {
    const value = JSON.parse(run(binary, [], { encoding: 'utf8', timeout: 1500, maxBuffer: 16384, stdio: ['ignore', 'pipe', 'pipe'] }));
    if (!value || Array.isArray(value) || typeof value !== 'object') return {};
    return Object.fromEntries(Object.entries(value).filter(([key, label]) => /^[A-Z0-9=\-\[\]'`;\\,/.]$/.test(key) && typeof label === 'string' && label.length > 0 && label.length <= 8 && !/[\r\n]/.test(label)));
  } catch { return {}; }
}
function physicalKey(label, keyLabels) { return Object.keys(keyLabels).find(key => keyLabels[key] === label) || label; }
module.exports = { readKeyLabels, physicalKey };
