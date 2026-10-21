const { spawn } = require('node:child_process');
const { createInterface } = require('node:readline');
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
function createWindowsFocus({ spawnImpl = spawn, timeoutMs = 2000 } = {}) {
  let child = null;
  let sequence = 0;
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
    const proc = spawnImpl('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    child = proc;
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
      const timer = setTimeout(() => { stop(); }, timeoutMs);
      pending.set(id, value => { clearTimeout(timer); resolve(value); });
      try { child.stdin.write(`${id} ${command}\n`, error => { if (error) stop(); }); }
      catch { stop(); }
    });
  }
  return { start, stop, capture: () => request('get'),
    restore: handle => /^\d+$/.test(String(handle)) && handle !== '0' ? request(`focus ${handle}`).then(value => value === '1') : Promise.resolve(false) };
}
async function pasteWindows({ text, target, clipboard, focus, hook }) {
  clipboard.writeText(text);
  try {
    if (!await focus.restore(target) || !hook) return false;
    // Recheck the captured handle immediately before generating Ctrl+V.
    if (await focus.capture() !== target) return false;
    hook.keyTap(47, [29]); // UiohookKey.V, UiohookKey.Ctrl
    return true; // OS dispatch succeeded; target app consumption cannot be observed.
  } catch { return false; }
}
module.exports = { createWindowsFocus, pasteWindows };
