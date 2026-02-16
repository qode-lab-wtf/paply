#!/usr/bin/env node
/**
 * Build script for the macOS Globe Key Listener.
 * Compiles the Swift source into a native binary at resources/bin/macos-globe-listener.
 * Only runs on macOS — skipped silently on other platforms.
 */
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const SRC = path.join(__dirname, '..', 'resources', 'bin', 'macos-globe-listener.swift');
const OUT = path.join(__dirname, '..', 'resources', 'bin', 'macos-globe-listener');

if (process.platform !== 'darwin') {
  console.log('[globe-listener] Skipping build — not on macOS');
  process.exit(0);
}

if (!fs.existsSync(SRC)) {
  console.error(`[globe-listener] Source not found: ${SRC}`);
  process.exit(1);
}

try {
  console.log('[globe-listener] Compiling Swift binary...');
  execSync(`swiftc -O -o "${OUT}" "${SRC}" -framework Cocoa -framework Carbon`, {
    stdio: 'inherit',
  });
  fs.chmodSync(OUT, 0o755);
  console.log(`[globe-listener] Built successfully: ${OUT}`);
} catch (err) {
  console.error('[globe-listener] Build failed:', err.message);
  console.error('[globe-listener] Make sure Xcode Command Line Tools are installed: xcode-select --install');
  process.exit(1);
}
