import { describe, it, expect } from 'vitest';
const { evaluateHealth } = require('./health-monitor.js');

const base = { micWriteOk: true, systemProcessAlive: true, systemPermissionDenied: false, diskError: false, micLevel: 0.2, systemLevel: 0.2, secondsSinceSystemAudio: 0 };

describe('evaluateHealth', () => {
  it('grün im Normalfall', () => { expect(evaluateHealth(base).color).toBe('green'); });
  it('rot bei fehlender Systemaudio-Berechtigung', () => {
    expect(evaluateHealth({ ...base, systemPermissionDenied: true }).color).toBe('red');
  });
  it('rot wenn Mic nicht gesichert wird', () => {
    expect(evaluateHealth({ ...base, micWriteOk: false }).color).toBe('red');
  });
  it('gelb bei langer System-Stille', () => {
    expect(evaluateHealth({ ...base, secondsSinceSystemAudio: 90 }).color).toBe('yellow');
  });
  it('rot bei AudioTee-Fehler (mit Grund im reason)', () => {
    const r = evaluateHealth({ ...base, systemAudioError: 'Failed to translate process IDs' });
    expect(r.color).toBe('red');
    expect(r.reason).toContain('Failed to translate');
  });
  it('gelb mit Setup-Hinweis, wenn nie System-Audio ankam', () => {
    const r = evaluateHealth({ ...base, gotSystemPcm: false, secondsSinceStart: 20, secondsSinceSystemAudio: 20 });
    expect(r.color).toBe('yellow');
    expect(r.reason).toContain('Mac');
  });
});

describe('health-monitor: Mikrofon-Bereitschaft', () => {
  const base = { micWriteOk: true, systemProcessAlive: true, systemPermissionDenied: false, diskError: false, micLevel: 0, systemLevel: 0, secondsSinceSystemAudio: 0 };
  it('gelb, wenn das Mikro nach 4 s noch nicht bereit ist', () => {
    expect(evaluateHealth({ ...base, micReady: false, secondsSinceStart: 5 }).color).toBe('yellow');
    expect(evaluateHealth({ ...base, micReady: false, secondsSinceStart: 2 }).color).toBe('green');
  });
  it('gelb mit Klartext bei verspätetem Mikro-Start', () => {
    const h = evaluateHealth({ ...base, micReady: true, micStartGapMs: 3993, secondsSinceStart: 6 });
    expect(h.color).toBe('yellow');
    expect(h.reason).toContain('4.0 s');
  });
});
