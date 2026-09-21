'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
function installRetentionAgent({ userData, executable, home, uid }) {
  const scripts = path.join(userData, 'retention-runtime'); fs.mkdirSync(scripts, { recursive: true });
  for (const name of ['local-retention.js','local-files.js']) fs.copyFileSync(path.join(__dirname, name), path.join(scripts, name));
  const esc = value => String(value).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&apos;' }[c]));
  const label = 'com.paply.meeting-test-audio-retention';
  const xml = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>${label}</string><key>ProgramArguments</key><array><string>${esc(executable)}</string><string>${esc(path.join(scripts,'local-retention.js'))}</string><string>${esc(path.join(userData,'meetings'))}</string></array><key>EnvironmentVariables</key><dict><key>ELECTRON_RUN_AS_NODE</key><string>1</string></dict><key>RunAtLoad</key><true/><key>StartInterval</key><integer>900</integer><key>ProcessType</key><string>Background</string><key>StandardErrorPath</key><string>${esc(path.join(userData,'retention-errors.log'))}</string></dict></plist>`;
  const folder = path.join(home,'Library','LaunchAgents'); fs.mkdirSync(folder,{recursive:true});
  const file = path.join(folder,label+'.plist');
  if (!fs.existsSync(file) || fs.readFileSync(file,'utf8') !== xml) {
    try { execFileSync('/bin/launchctl',['bootout',`gui/${uid}/${label}`],{stdio:'ignore'}); } catch {}
    fs.writeFileSync(file,xml,{mode:0o600});
  }
  try { execFileSync('/bin/launchctl',['print',`gui/${uid}/${label}`],{stdio:'ignore'}); }
  catch { execFileSync('/bin/launchctl',['bootstrap',`gui/${uid}`,file],{stdio:'ignore'}); }
  return file;
}
module.exports = { installRetentionAgent };
