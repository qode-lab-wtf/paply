// 16-bit PCM <-> WAV. CommonJS.
'use strict';

const fs = require('node:fs');

/** Baut einen 44-Byte-RIFF/WAVE-Header für `dataLength` Bytes PCM. */
function wavHeader(dataLength, { sampleRate = 16000, channels = 1 } = {}) {
  const byteRate = sampleRate * channels * 2;
  const blockAlign = channels * 2;
  const header = Buffer.alloc(44);
  header.write('RIFF', 0, 'ascii');
  header.writeUInt32LE(36 + dataLength, 4);
  header.write('WAVE', 8, 'ascii');
  header.write('fmt ', 12, 'ascii');
  header.writeUInt32LE(16, 16); // fmt chunk size
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(16, 34); // bits per sample
  header.write('data', 36, 'ascii');
  header.writeUInt32LE(dataLength, 40);
  return header;
}

/** 16-bit-PCM-Buffer -> komplette WAV (Header + Daten). */
function encodeWav(pcmBuffer, opts) {
  return Buffer.concat([wavHeader(pcmBuffer.length, opts), pcmBuffer]);
}

/** Mehrere reine PCM-Buffer zu einer WAV zusammenfügen. */
function concatWav(pcmBuffers, opts) {
  return encodeWav(Buffer.concat(pcmBuffers), opts);
}

/**
 * Fügt mehrere WAV-DATEIEN (gleiches Format) zu einer einzigen WAV zusammen –
 * streaming, mit konstantem Speicherbedarf (jeweils nur eine Datei im RAM).
 * Ideal für sehr lange Meetings: keine RAM-Akkumulation aller Audiodaten.
 * Erwartet Standard-44-Byte-WAV-Header in den Eingabedateien (PCM ab Byte 44).
 * @returns {number} Gesamt-PCM-Bytegröße
 */
function concatWavFiles(inputWavPaths, outPath, { sampleRate = 16000, channels = 1 } = {}) {
  // 1) Header mit Platzhalter-Größe schreiben
  fs.writeFileSync(outPath, wavHeader(0, { sampleRate, channels }));
  // 2) PCM jeder Quelldatei (ohne deren Header) anhängen
  let dataLength = 0;
  for (const p of inputWavPaths) {
    const buf = fs.readFileSync(p);
    if (buf.length <= 44) continue; // leer/kaputt -> überspringen
    const pcm = buf.subarray(44);
    fs.appendFileSync(outPath, pcm);
    dataLength += pcm.length;
  }
  // 3) Größenfelder im Header nachtragen (RIFF @4, data @40)
  const fd = fs.openSync(outPath, 'r+');
  try {
    const sizeBuf = Buffer.alloc(4);
    sizeBuf.writeUInt32LE(36 + dataLength, 0);
    fs.writeSync(fd, sizeBuf, 0, 4, 4);
    sizeBuf.writeUInt32LE(dataLength, 0);
    fs.writeSync(fd, sizeBuf, 0, 4, 40);
  } finally {
    fs.closeSync(fd);
  }
  return dataLength;
}

/** Liest einen Zeitausschnitt (reines PCM, ohne Header) aus einer 16-bit-Mono-WAV (44-Byte-Header). */
function readWavSlice(wavPath, startSec, endSec, sampleRate = 16000) {
  const size = fs.statSync(wavPath).size;
  const dataBytes = Math.max(0, size - 44);
  const a = Math.min(dataBytes, Math.max(0, Math.floor(startSec * sampleRate) * 2));
  const b = Math.min(dataBytes, Math.max(a, Math.floor(endSec * sampleRate) * 2));
  const buf = Buffer.alloc(b - a);
  if (b > a) {
    const fd = fs.openSync(wavPath, 'r');
    try { fs.readSync(fd, buf, 0, b - a, 44 + a); } finally { fs.closeSync(fd); }
  }
  return buf;
}

/** Dauer einer 16-bit-Mono-WAV in Sekunden (0, wenn nicht vorhanden). */
function wavDurationSec(wavPath, sampleRate = 16000) {
  try { return Math.max(0, fs.statSync(wavPath).size - 44) / 2 / sampleRate; } catch { return 0; }
}

/** Liest Format-Infos aus dem 44-Byte-Header (für Prüfungen im CLI). */
function wavInfo(wavPath) {
  const fd = fs.openSync(wavPath, 'r');
  try {
    const h = Buffer.alloc(44); fs.readSync(fd, h, 0, 44, 0);
    return { channels: h.readUInt16LE(22), sampleRate: h.readUInt32LE(24), bitsPerSample: h.readUInt16LE(34), format: h.readUInt16LE(20) };
  } finally { fs.closeSync(fd); }
}

module.exports = { wavHeader, encodeWav, concatWav, concatWavFiles, readWavSlice, wavDurationSec, wavInfo };
