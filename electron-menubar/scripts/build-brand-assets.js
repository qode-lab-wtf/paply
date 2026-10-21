#!/usr/bin/env node
/**
 * Erzeugt alle Icon-Dateien für App und Build aus den SVG-Quellen in brand/.
 * Aufruf: npm run build:brand
 *
 *   icon.icns                macOS-App-Icon (nur auf macOS, braucht `iconutil`)
 *   icon.png, icon_*.png     PNGs 16–1024 (≤ 32 px: vereinfachte Zeichnung)
 *   icon.ico                 Windows-App-/Installer-Icon (16–256)
 *   tray.ico                 Windows-Tray, farbig (16–48 = 100–300 % Skalierung)
 *   iconTemplate(@2x).png    macOS-Menüleiste, Template-Bild (22 / 44 px)
 */
const sharp = require('sharp');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const BRAND = path.join(ROOT, 'brand');
const svg = (name) => fs.readFileSync(path.join(BRAND, name));

const SRC = {
  app: svg('app-icon.svg'), // 1024, macOS-Raster mit Schattenrand
  appWin: svg('app-icon-windows.svg'), // randlos, ohne Schlagschatten
  small: svg('app-icon-small.svg'), // vereinfachte Zeichnung, 32er-Raster
  trayColor: svg('tray-color.svg'), // Windows-Tray, 32er-Raster
  trayTemplate: svg('tray-template.svg'), // macOS-Menüleiste, 22er-Raster
};
const VIEWBOX = { app: 1024, appWin: 824, small: 32, trayColor: 32, trayTemplate: 22 };

// SVG direkt in Zielgröße rastern (librsvg glättet dann für genau diese Pixelgröße)
async function render(key, size) {
  const density = (72 * size) / VIEWBOX[key];
  return sharp(SRC[key], { density })
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toBuffer();
}

// ICO mit PNG-Einträgen (Windows Vista und neuer)
function buildIco(images) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  const dir = Buffer.alloc(16 * images.length);
  let offset = 6 + dir.length;
  images.forEach(({ size, buffer }, i) => {
    const o = i * 16;
    dir.writeUInt8(size >= 256 ? 0 : size, o);
    dir.writeUInt8(size >= 256 ? 0 : size, o + 1);
    dir.writeUInt8(0, o + 2);
    dir.writeUInt8(0, o + 3);
    dir.writeUInt16LE(1, o + 4);
    dir.writeUInt16LE(32, o + 6);
    dir.writeUInt32LE(buffer.length, o + 8);
    dir.writeUInt32LE(offset, o + 12);
    offset += buffer.length;
  });
  return Buffer.concat([header, dir, ...images.map((im) => im.buffer)]);
}

const out = (name, buf) => {
  fs.writeFileSync(path.join(ROOT, name), buf);
  console.log(`  ${name.padEnd(24)} ${(buf.length / 1024).toFixed(1)} KB`);
};
// ≤ 32 px: kleine Zeichnung (größeres Auge, Fläche randlos), sonst das große Icon
const appKey = (size) => (size <= 32 ? 'small' : 'app');
const winKey = (size) => (size <= 32 ? 'small' : 'appWin');

async function main() {
  console.log('paply · Marken-Assets aus brand/*.svg');

  // PNGs (macOS-Raster) – icon.png ist die 512er-Fassung für Linux/Fallback
  for (const size of [16, 32, 64, 128, 256, 512, 1024]) {
    out(`icon_${size}x${size}.png`, await render(appKey(size), size));
  }
  out('icon.png', await render('app', 512));

  // Windows-App-Icon (auch NSIS-Installer)
  const icoSizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
  out('icon.ico', buildIco(await Promise.all(icoSizes.map(async (size) => ({ size, buffer: await render(winKey(size), size) })))));

  // Windows-Tray
  const traySizes = [16, 20, 24, 32, 40, 48];
  out('tray.ico', buildIco(await Promise.all(traySizes.map(async (size) => ({ size, buffer: await render('trayColor', size) })))));

  // macOS-Menüleiste: Template-Bild, 22 pt (Glyphe ~18 pt hoch)
  out('iconTemplate.png', await render('trayTemplate', 22));
  out('iconTemplate@2x.png', await render('trayTemplate', 44));

  // macOS .icns über iconutil
  if (process.platform !== 'darwin') {
    console.log('  icon.icns                übersprungen (iconutil gibt es nur auf macOS)');
    return;
  }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-icns-'));
  const set = path.join(tmp, 'icon.iconset');
  fs.mkdirSync(set);
  for (const pt of [16, 32, 128, 256, 512]) {
    fs.writeFileSync(path.join(set, `icon_${pt}x${pt}.png`), await render(appKey(pt), pt));
    fs.writeFileSync(path.join(set, `icon_${pt}x${pt}@2x.png`), await render(appKey(pt * 2), pt * 2));
  }
  execFileSync('iconutil', ['-c', 'icns', set, '-o', path.join(ROOT, 'icon.icns')]);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`  icon.icns                ${(fs.statSync(path.join(ROOT, 'icon.icns')).size / 1024).toFixed(1)} KB`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
