const { execFileSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
if (process.platform === 'darwin') {
  const dir = path.join(__dirname, '..', 'resources', 'bin');
  const out = path.join(dir, 'macos-notes-keymap');
  execFileSync('swiftc', ['-O', path.join(dir, 'macos-notes-keymap.swift'), '-o', out, '-framework', 'Carbon'], { stdio: 'inherit' });
  fs.chmodSync(out, 0o755);
  console.log('[notes] Keyboard layout helper built');
}
