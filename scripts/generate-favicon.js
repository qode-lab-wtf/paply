const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

// SVG für Favicon (Papagei ohne Hintergrund für bessere Sichtbarkeit bei kleinen Größen)
const faviconSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
  <!-- paply Favicon: Papagei kompakt -->
  
  <!-- Hintergrund -->
  <rect width="32" height="32" rx="6" fill="#4CAF50"/>
  
  <!-- Papagei -->
  <g transform="translate(3, 4)">
    <!-- Kopf -->
    <path d="M4 0 C1 0, 0 3, 0 8 C0 13, 2 15, 8 15 L12 15 L12 8 C12 3, 9 0, 4 0 Z" fill="#8BC34A"/>
    
    <!-- Auge -->
    <circle cx="5" cy="7" r="2.5" fill="white"/>
    <circle cx="5" cy="7" r="1.2" fill="#1A237E"/>
    
    <!-- Schnabel -->
    <path d="M12 5 L20 8 L20 9 L12 11 Z" fill="#FDD835"/>
    <path d="M12 11 L20 9 L16 13 L12 14 Z" fill="#F9A825"/>
    
    <!-- Mundbereich -->
    <path d="M10 9 L12 8 L12 12 L10 11 Z" fill="#1A237E"/>
  </g>
</svg>`;

async function generateFavicons() {
  const outputDir = path.join(__dirname, '..', 'src', 'app');
  
  // Stelle sicher, dass das Verzeichnis existiert
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const svgBuffer = Buffer.from(faviconSvg);

  // Generiere PNG in verschiedenen Größen
  const sizes = [16, 32, 48, 64, 128, 256];
  
  for (const size of sizes) {
    await sharp(svgBuffer)
      .resize(size, size)
      .png()
      .toFile(path.join(outputDir, `favicon-${size}.png`));
    console.log(`Generated favicon-${size}.png`);
  }

  // Generiere das Haupt-favicon.png (32x32)
  await sharp(svgBuffer)
    .resize(32, 32)
    .png()
    .toFile(path.join(outputDir, 'favicon.png'));
  console.log('Generated favicon.png');

  // Für ICO: Wir erstellen eine 32x32 PNG, die als favicon.ico verwendet werden kann
  // (Browser akzeptieren auch PNG-Dateien mit .ico Endung)
  await sharp(svgBuffer)
    .resize(32, 32)
    .png()
    .toFile(path.join(outputDir, 'favicon.ico'));
  console.log('Generated favicon.ico (PNG format)');

  console.log('\nDone! Favicons generated in src/app/');
}

generateFavicons().catch(console.error);
