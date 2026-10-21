const { spawn } = require('node:child_process');

function captureMacApp({ spawnImpl = spawn, timeoutMs = 2000 } = {}) {
  return new Promise(resolve => {
    try {
      const proc = spawnImpl('osascript', ['-e', 'tell application "System Events" to get name of first application process whose frontmost is true']);
      const timer = setTimeout(() => { proc.kill(); resolve(null); }, timeoutMs);
      let output = '';
      proc.stdout.on('data', data => { output += data.toString(); });
      proc.on('error', () => { clearTimeout(timer); resolve(null); });
      proc.on('close', code => { clearTimeout(timer); resolve(code === 0 ? output.trim() || null : null); });
    } catch { resolve(null); }
  });
}

function pasteMac(target, { spawnImpl = spawn, timeoutMs = 5000 } = {}) {
  // Same focus command, same Cmd+V and same delays as the established Mac path.
  const name = target?.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const script = name
    ? `tell application "System Events"
           set frontmost of process "${name}" to true
           delay 0.3
           keystroke "v" using command down
         end tell`
    : `delay 0.2
         tell application "System Events" to keystroke "v" using command down`;
  return new Promise(resolve => {
    setTimeout(() => {
      try {
        const proc = spawnImpl('osascript', ['-e', script]);
        const timer = setTimeout(() => { proc.kill(); resolve(false); }, timeoutMs);
        let failed = false;
        proc.stderr.on('data', data => { if (data.toString().trim()) failed = true; });
        proc.on('error', () => { clearTimeout(timer); resolve(false); });
        proc.on('close', code => { clearTimeout(timer); resolve(code === 0 && !failed); });
      } catch { resolve(false); }
    }, 150);
  });
}
module.exports = { captureMacApp, pasteMac };
