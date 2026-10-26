'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { assert, id, uid, node } = require('./contracts');
const { atomic } = require('./repo');
const { encodeWav } = require('../audio/wav-encoder');
function createAssets({ repo, nativeImage, desktopCapturer, screen, commands, getSettings }) {
  function put(bytes) {
    assert(bytes instanceof ArrayBuffer || ArrayBuffer.isView(bytes) || Buffer.isBuffer(bytes));
    const input = Buffer.from(bytes instanceof ArrayBuffer ? bytes : new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength));
    assert(input.length > 8 && input.length <= 25 * 1024 * 1024, 'Bild ist zu groß (maximal 25 MB).');
    const magic = input.subarray(0, 12);
    assert(magic.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || magic[0] === 255 && magic[1] === 216 || magic.toString('ascii',0,3) === 'GIF' || magic.toString('ascii',0,4) === 'RIFF' && magic.toString('ascii',8,12) === 'WEBP', 'Nur PNG, JPEG, GIF oder WebP möglich.');
    let image = nativeImage.createFromBuffer(input); assert(!image.isEmpty(), 'Bild konnte nicht gelesen werden.');
    const size = image.getSize(); assert(size.width * size.height <= 60e6, 'Bildauflösung ist zu groß.');
    if (Math.max(size.width, size.height) > 2400) image = image.resize(size.width >= size.height ? { width: 2400 } : { height: 2400 });
    const png = image.toPNG(), hash = crypto.createHash('sha256').update(png).digest('hex');
    const file = path.join(repo.root, 'assets', `${hash}.png`);
    if (!fs.existsSync(file)) { const fd = fs.openSync(file, 'wx', 0o600); try { fs.writeFileSync(fd, png); fs.fsyncSync(fd); } finally { fs.closeSync(fd); } }
    const thumb = image.resize(image.getSize().width >= image.getSize().height ? { width: 240 } : { height: 240 }).toJPEG(80);
    fs.writeFileSync(path.join(repo.root, 'thumbs', `${hash}.jpg`), thumb, { mode: 0o600 });
    const metaFile = path.join(repo.root, 'assets', `${hash}.json`);
    if (!fs.existsSync(metaFile)) atomic(metaFile, { id: hash, createdAt: Date.now(), size: image.getSize(), analysis: null, attempts: 0 });
    return hash;
  }
  async function screenshot() {
    const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: Math.min(1920, display.size.width), height: Math.min(1440, display.size.height) } });
    const source = sources.find(s => String(s.display_id) === String(display.id));
    assert(source && !source.thumbnail.isEmpty(), 'Bildschirmzugriff fehlt. In den Systemeinstellungen erlauben.'); return source.thumbnail.toPNG();
  }
  function attach(hash, target, position) {
    assert(/^[a-f0-9]{64}$/.test(hash));
    return commands.commit(b => {
      if (target) { const n = b.nodes[id(target)]; assert(n, 'Notiz wurde entfernt.'); if (!n.attachments.includes(hash)) n.attachments.push(hash); n.pinned = true; n.rev++; }
      else { const n = node({ kind: 'image', text: '', label: '', position }); n.attachments = [hash]; b.nodes[n.id] = n; }
    });
  }
  async function serve(request) {
    const url = new URL(request.url); const name = `${url.hostname}${url.pathname}`;
    let match = /^(asset|thumb)\/([a-f0-9]{64})$/.exec(name);
    if (match) {
      const thumb = match[1] === 'thumb'; const file = path.join(repo.root, thumb ? 'thumbs' : 'assets', `${match[2]}.${thumb ? 'jpg' : 'png'}`);
      try { return new Response(fs.readFileSync(file), { headers: { 'Content-Type': thumb ? 'image/jpeg' : 'image/png', 'Cache-Control': 'private, max-age=31536000', 'X-Content-Type-Options': 'nosniff' } }); } catch { return new Response(null, { status: 404 }); }
    }
    match = /^audio\/([\w-]{1,100})$/.exec(name);
    if (match) {
      try { const entry = repo.entry(match[1]); assert(entry && entry.state !== 'discarded'); const audio = encodeWav(fs.readFileSync(path.join(repo.sourcePath(entry.id), 'rec.pcm'))); return new Response(audio, { headers: { 'Content-Type': 'audio/wav' } }); } catch { return new Response(null, { status: 404 }); }
    }
    return new Response(null, { status: 403 });
  }
  return { put, attach, screenshot, serve,
    async camera(target, position) { return attach(put(await screenshot()), target, position); },
    pending() {
      if (!getSettings().imageUnderstanding) return [];
      const used = new Set(Object.values(repo.current().nodes).flatMap(n => n.attachments));
      return [...used].map(hash => repo.readLocal(`assets/${hash}.json`, null)).filter(m => m && !m.analysis && m.attempts < 3 && (!m.retryAt || m.retryAt < Date.now()));
    },
    describeInput(hash) { assert(/^[a-f0-9]{64}$/.test(hash)); let img = nativeImage.createFromPath(path.join(repo.root, 'assets', `${hash}.png`)); const size = img.getSize(); if (Math.max(size.width, size.height) > 1568) img = img.resize(size.width >= size.height ? { width: 1568 } : { height: 1568 }); return `data:image/jpeg;base64,${img.toJPEG(85).toString('base64')}`; },
  };
}
module.exports = { createAssets };
