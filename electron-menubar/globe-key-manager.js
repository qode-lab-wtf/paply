/**
 * GlobeKeyManager — manages the native macOS Globe/Fn key listener subprocess.
 * Emits 'globe-down' and 'globe-up' events that the main process can react to.
 * Only supported on macOS; no-ops silently on other platforms.
 */
const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const EventEmitter = require('node:events');

class GlobeKeyManager extends EventEmitter {
  constructor() {
    super();
    this.process = null;
    this.isSupported = process.platform === 'darwin';
  }

  start() {
    if (!this.isSupported || this.process) return;

    const binaryPath = this._resolveBinary();
    if (!binaryPath) {
      console.warn('[GlobeKeyManager] Binary not found — Globe key disabled');
      console.warn('[GlobeKeyManager] Run: node scripts/build-globe-listener.js');
      return;
    }

    // Ensure it's executable
    try {
      fs.accessSync(binaryPath, fs.constants.X_OK);
    } catch {
      try {
        fs.chmodSync(binaryPath, 0o755);
      } catch (err) {
        console.error('[GlobeKeyManager] Cannot make binary executable:', err.message);
        return;
      }
    }

    this.process = spawn(binaryPath, [], { stdio: ['ignore', 'pipe', 'pipe'] });

    this.process.stdout.setEncoding('utf8');
    this.process.stdout.on('data', (chunk) => {
      chunk.split(/\r?\n/).filter(Boolean).forEach((line) => {
        const trimmed = line.trim();
        if (trimmed === 'FN_DOWN') {
          this.emit('globe-down');
        } else if (trimmed === 'FN_UP') {
          this.emit('globe-up');
        }
      });
    });

    this.process.stderr.setEncoding('utf8');
    this.process.stderr.on('data', (data) => {
      console.error('[GlobeKeyManager] stderr:', data.trim());
    });

    this.process.on('error', (err) => {
      console.error('[GlobeKeyManager] Process error:', err.message);
      this.process = null;
    });

    this.process.on('exit', (code, signal) => {
      this.process = null;
      if (code !== 0 && signal !== 'SIGINT' && signal !== 'SIGTERM') {
        console.error(`[GlobeKeyManager] Exited with code ${code}, signal ${signal}`);
      }
    });

    console.log('[GlobeKeyManager] Globe key listener started');
  }

  stop() {
    if (this.process) {
      this.process.kill();
      this.process = null;
      console.log('[GlobeKeyManager] Globe key listener stopped');
    }
  }

  get isRunning() {
    return this.process !== null;
  }

  _resolveBinary() {
    const candidates = [
      // Development: next to source
      path.join(__dirname, 'resources', 'bin', 'macos-globe-listener'),
      // Packaged app: extraResources
      ...(process.resourcesPath ? [
        path.join(process.resourcesPath, 'bin', 'macos-globe-listener'),
        path.join(process.resourcesPath, 'macos-globe-listener'),
        path.join(process.resourcesPath, 'app.asar.unpacked', 'resources', 'bin', 'macos-globe-listener'),
      ] : []),
    ];

    for (const candidate of candidates) {
      try {
        if (fs.statSync(candidate).isFile()) return candidate;
      } catch {
        continue;
      }
    }
    return null;
  }
}

module.exports = GlobeKeyManager;
