const { spawn } = require('node:child_process');
const { createInterface } = require('node:readline');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
// One process + one Add-Type per application lifetime. Only numeric handles cross
// stdin/stdout; no dictated text or dynamically evaluated commands reach PowerShell.
const script = `
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PaplyFocus {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
'@
while ($null -ne ($line = [Console]::ReadLine())) {
 try {
  $p = $line.Split(' '); $id = $p[0]; $value = '0'
  if ($p[1] -eq 'get') { $value = [PaplyFocus]::GetForegroundWindow().ToInt64().ToString() }
  elseif ($p[1] -eq 'focus') {
   $h = [IntPtr]::new([long]::Parse($p[2]))
   if ([PaplyFocus]::IsWindow($h)) {
    $null = [PaplyFocus]::SetForegroundWindow($h)
    for ($i=0; $i -lt 5; $i++) {
     if ([PaplyFocus]::GetForegroundWindow() -eq $h) { $value='1'; break }
     Start-Sleep -Milliseconds 10
    }
   }
  }
  [Console]::WriteLine($id + ' ' + $value)
 } catch { [Console]::WriteLine($id + ' 0') }
}
`;
function createWindowsFocus({ spawnImpl = spawn, timeoutMs = 2000, coldTimeoutMs = 6000,
  scriptDirectory = () => path.join(os.tmpdir(), 'paply-focus') } = {}) {
  let child = null;
  let sequence = 0;
  let coldRequest = true;
  const pending = new Map();
  function stop() {
    const old = child;
    child = null;
    for (const resolve of pending.values()) resolve(null);
    pending.clear();
    old?.kill(); // only this owned child PID
  }
  function start() {
    if (child) return;
    // A plain local script avoids EncodedCommand heuristics in antivirus tools.
    // stdin remains exclusively the numeric request protocol.
    const directory = scriptDirectory();
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    const scriptPath = path.join(directory, 'dictation-focus.ps1');
    fs.writeFileSync(scriptPath, script, { encoding: 'utf8', mode: 0o600 });
    const proc = spawnImpl('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptPath], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    child = proc;
    coldRequest = true;
    const fail = () => { if (child === proc) stop(); };
    proc.on('error', fail); proc.on('exit', fail);
    proc.stdin.on('error', fail);
    proc.stdout.on('error', fail);
    proc.stderr.on('data', () => {});
    const lines = createInterface({ input: proc.stdout });
    lines.on('line', line => {
      const match = /^(\d+) (\d+)$/.exec(line.trim());
      if (!match) return;
      pending.get(match[1])?.(match[2]);
      pending.delete(match[1]);
    });
  }
  async function request(command) {
    try { start(); } catch { return null; }
    return new Promise(resolve => {
      const id = String(++sequence);
      const duration = coldRequest ? coldTimeoutMs : timeoutMs;
      coldRequest = false;
      const timer = setTimeout(() => {
        // A slow request must not kill the shared helper or unrelated requests.
        pending.get(id)?.(null);
        pending.delete(id);
      }, duration);
      pending.set(id, value => { clearTimeout(timer); resolve(value); });
      try { child.stdin.write(`${id} ${command}\n`, error => { if (error) stop(); }); }
      catch { stop(); }
    });
  }
  return { start, stop, capture: () => request('get'),
    restore: handle => /^\d+$/.test(String(handle)) && handle !== '0' ? request(`focus ${handle}`).then(value => value === null ? null : value === '1') : Promise.resolve(false) };
}
async function pasteWindows({ text, target, clipboard, focus, hook }) {
  clipboard.writeText(text);
  try {
    if (!hook) return false;
    if (target != null && target !== '0') {
      // One restore request includes SetForegroundWindow + verification in the
      // helper. No second capture (and no retry loop) on the paste path.
      let restored = null;
      try { restored = await focus.restore(target); } catch { /* helper unavailable: current-window fallback */ }
      if (restored === false) return false;
    }
    // Without a captured target, retain the established current-window paste.
    hook.keyTap(47, [29]); // UiohookKey.V, UiohookKey.Ctrl
    return true; // OS dispatch succeeded; target app consumption cannot be observed.
  } catch { return false; }
}
module.exports = { createWindowsFocus, pasteWindows };
