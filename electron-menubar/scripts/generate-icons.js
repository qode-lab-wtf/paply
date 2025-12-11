const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

// Paply App Icon SVG (farbiger Papagei)
const appIconSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#A5D6A7"/>
      <stop offset="100%" style="stop-color:#81C784"/>
    </linearGradient>
  </defs>
  
  <!-- Hintergrund mit abgerundeten Ecken -->
  <rect width="512" height="512" rx="110" fill="url(#bgGrad)"/>
  
  <!-- Papagei -->
  <g transform="translate(80, 70)">
    <!-- Kopf dunkelgruen -->
    <path d="M60 0 
             C20 0, -20 60, -20 150
             C-20 240, 40 290, 140 290
             L200 290
             L200 150
             C200 60, 140 0, 60 0 Z" 
          fill="#4CAF50"/>
    
    <!-- Kopf hellgruen -->
    <path d="M60 0 
             C20 0, -20 60, -20 150
             C-20 200, 10 230, 60 230
             L120 230
             L120 80
             C120 30, 90 0, 60 0 Z" 
          fill="#8BC34A"/>
    
    <!-- Auge weiss -->
    <ellipse cx="70" cy="130" rx="40" ry="40" fill="white"/>
    
    <!-- Auge pupille -->
    <circle cx="70" cy="130" r="20" fill="#1A237E"/>
    
    <!-- Schnabel oben -->
    <path d="M200 100
             L340 150
             L340 175
             L200 210
             Z" 
          fill="#FDD835"/>
    
    <!-- Schnabel unten -->
    <path d="M200 210
             L340 175
             L280 240
             L200 270
             Z" 
          fill="#F9A825"/>
    
    <!-- Mundbereich -->
    <path d="M170 180
             L200 165
             L200 240
             L170 220
             Z" 
          fill="#1A237E"/>
  </g>
</svg>`;

// Template Icon SVG (schwarz, fuer Menueleiste)
const templateIconSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">
  <!-- Papagei Kopf -->
  <path d="M5 3 
           C3 3, 2 5, 2 8
           C2 11, 4 13, 7 13
           L10 13
           L10 8
           C10 5, 8 3, 5 3 Z" 
        fill="black"/>
  
  <!-- Auge -->
  <circle cx="5.5" cy="7.5" r="1.8" fill="white"/>
  <circle cx="5.5" cy="7.5" r="0.9" fill="black"/>
  
  <!-- Schnabel -->
  <path d="M10 6 L16 8 L16 9 L10 10.5 Z" fill="black"/>
  <path d="M10 10.5 L16 9 L13 11.5 L10 12.5 Z" fill="black"/>
</svg>`;

async function generateIcons() {
  const outputDir = path.join(__dirname, '..');
  
  const appIconBuffer = Buffer.from(appIconSvg);
  const templateIconBuffer = Buffer.from(templateIconSvg);

  // App Icons in verschiedenen Groessen
  const appSizes = [16, 32, 64, 128, 256, 512, 1024];
  
  for (const size of appSizes) {
    await sharp(appIconBuffer)
      .resize(size, size)
      .png()
      .toFile(path.join(outputDir, `icon_${size}x${size}.png`));
    console.log(`Generated icon_${size}x${size}.png`);
  }

  // Haupt icon.png (512x512)
  await sharp(appIconBuffer)
    .resize(512, 512)
    .png()
    .toFile(path.join(outputDir, 'icon.png'));
  console.log('Generated icon.png');

  // Template Icons fuer Menueleiste (18x18 und 36x36 fuer Retina)
  await sharp(templateIconBuffer)
    .resize(18, 18)
    .png()
    .toFile(path.join(outputDir, 'iconTemplate.png'));
  console.log('Generated iconTemplate.png');

  await sharp(templateIconBuffer)
    .resize(36, 36)
    .png()
    .toFile(path.join(outputDir, 'iconTemplate@2x.png'));
  console.log('Generated iconTemplate@2x.png');

  console.log('\\nDone! All icons generated.');
  console.log('\\nNOTE: For Windows icon.ico, run: npm run generate:ico');
  console.log('NOTE: For macOS icon.icns, rebuild the app with: npm run build');
}

generateIcons().catch(console.error);
