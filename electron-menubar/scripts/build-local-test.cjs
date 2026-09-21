// Separate local app identity. Never publishes, notarizes, or replaces /Applications/paply.app.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const runtime = path.resolve(process.argv[2] || '../work/local-runtime.json');
const output = path.resolve(process.argv[3] || '../work/local-test-build');
const config = JSON.parse(fs.readFileSync(runtime, 'utf8'));
for (const key of ['asrPython', 'diarizationPython', 'whisperModel', 'pyannoteModel']) {
  if (!config[key] || !fs.existsSync(config[key])) throw new Error(`Missing local runtime: ${key}`);
}
const build = JSON.parse(JSON.stringify(require('../package.json').build));
build.appId = 'com.paply.meeting.localtest';
// Electron 33 crashes before ready with a non-ASCII executable name on this host.
build.productName = 'Paply Meeting Test';
build.publish = null;
build.afterSign = null;
build.directories = { ...build.directories, output };
build.mac.identity = null;
build.mac.extraResources = [...(build.mac.extraResources || []), { from: runtime, to: 'local-runtime.json' }];
fs.mkdirSync(output, { recursive: true });
const builderConfig = path.join(output, 'local-builder.json');
fs.writeFileSync(builderConfig, JSON.stringify(build, null, 2));
const run = (exe, args, extra={}) => execFileSync(exe,args,{cwd:root,stdio:'inherit',...extra});
run('npm',['run','compile:bin']);
run('npm',['run','vite:build']);
run(path.join(root,'node_modules/.bin/electron-builder'),['--dir','--mac','--arm64','--publish','never','--config',builderConfig],{env:{...process.env,CSC_IDENTITY_AUTO_DISCOVERY:'false'}});
const app=path.join(output,'mac-arm64','Paply Meeting Test.app');
run('/usr/bin/codesign',['--force','--deep','--sign','-','--entitlements','entitlements.mac.plist',app]);
run('/usr/bin/codesign',['--verify','--deep','--strict',app]);
console.log(`Test application: ${app}`);
