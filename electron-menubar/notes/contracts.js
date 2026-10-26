'use strict';
const crypto = require('node:crypto');
const ID = /^[a-zA-Z0-9_-]{1,100}$/;
const KINDS = ['note', 'sticky', 'text', 'hub', 'table', 'image', 'point'];
const ICONS = ['sparkles', 'lightbulb', 'home', 'code', 'map-pin', 'sun', 'moon', 'heart', 'coffee', 'briefcase', 'calendar', 'message-circle', 'book', 'music', 'camera', 'leaf', 'flag', 'circle-help', 'pencil', 'plane', 'wallet', 'users', 'list', 'zap'];
const uid = (prefix = 'n') => `${prefix}_${crypto.randomUUID().replaceAll('-', '')}`;
const clone = (value) => structuredClone(value);
function assert(ok, message = 'Ungültige Notes-Daten') { if (!ok) throw new Error(message); }
function id(value) { assert(typeof value === 'string' && ID.test(value) && !Object.hasOwn(Object.prototype, value) && value !== 'prototype'); return value; }
function text(value, max = 20000) { assert(typeof value === 'string' && value.length <= max); return value; }
function point(value) { assert(value && Number.isFinite(value.x) && Number.isFinite(value.y) && Math.abs(value.x) <= 1e7 && Math.abs(value.y) <= 1e7); return { x: value.x, y: value.y }; }
function blankBoard() { return { schemaVersion: 1, rev: 0, nodes: {}, edges: {}, topics: {}, claims: {}, tombstones: {}, viewport: { x: 90, y: 100, zoom: 1 } }; }
function validBoard(b) {
  try {
    assert(b && b.schemaVersion === 1 && Number.isInteger(b.rev) && b.rev >= 0);
    for (const table of ['nodes', 'edges', 'topics', 'claims', 'tombstones']) {
      assert(b[table] && typeof b[table] === 'object' && !Array.isArray(b[table])); Object.keys(b[table]).forEach(id);
    }
    point(b.viewport); assert(Number.isFinite(b.viewport.zoom) && b.viewport.zoom >= .1 && b.viewport.zoom <= 2.5);
    for (const [key, n] of Object.entries(b.nodes)) {
      assert(n && n.id === key && KINDS.includes(n.kind)); text(n.text, 650000); text(n.label, 80);
      assert(ICONS.includes(n.icon) && ['user', 'ai', 'system'].includes(n.owner) && Number.isInteger(n.rev) && n.rev > 0 && Number.isFinite(n.createdAt));
      if (n.position !== null) point(n.position);
      assert(Number.isFinite(n.width) && n.width >= 12 && n.width <= 5000 && (n.height === null || Number.isFinite(n.height) && n.height >= 12 && n.height <= 5000));
      if (n.topicId !== null) { id(n.topicId); assert(b.topics[n.topicId]); }
      if (n.sourceId !== null) id(n.sourceId);
      assert(Array.isArray(n.sentenceIds) && Array.isArray(n.attachments)); n.sentenceIds.forEach(id);
      assert(n.attachments.every(hash => typeof hash === 'string' && /^[a-f0-9]{64}$/.test(hash)));
      if (n.kind === 'table') patch({ table: n.table });
    }
    for (const [key, e] of Object.entries(b.edges)) {
      assert(e && e.id === key && b.nodes[id(e.source)] && b.nodes[id(e.target)]);
      assert(['left', 'right'].includes(e.sourceHandle) && ['left', 'right'].includes(e.targetHandle) && typeof e.arrow === 'boolean' && typeof e.inferred === 'boolean'); text(e.label, 80);
    }
    for (const [key, t] of Object.entries(b.topics)) { assert(t && t.id === key && ICONS.includes(t.icon)); text(t.title, 80); }
    for (const claim of Object.values(b.claims)) assert(typeof claim === 'string' ? b.nodes[id(claim)] : claim && claim.tomb === true);
    assert(Object.values(b.tombstones).every(Number.isFinite)); return true;
  } catch { return false; }
}
function node(input, now = Date.now()) {
  assert(input && KINDS.includes(input.kind));
  const result = { id: uid(), kind: input.kind, text: text(input.text || ''), label: text(input.label || '', 80), icon: ICONS.includes(input.icon) ? input.icon : 'pencil', position: input.position == null ? null : point(input.position), width: input.kind === 'table' ? 580 : input.kind === 'point' ? 12 : 320, height: null, topicId: input.topicId ? id(input.topicId) : null, sourceId: null, sentenceIds: [], attachments: [], owner: 'user', rev: 1, createdAt: now };
  if (input.kind === 'table') result.table = { columns: ['Option A', 'Option B'], rows: [{ label: 'Gedanke', cells: ['', ''] }] };
  return result;
}
function patch(input) {
  assert(input && typeof input === 'object' && !Array.isArray(input));
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'text') result.text = text(value);
    else if (key === 'label') result.label = text(value, 80);
    else if (key === 'position') result.position = point(value);
    else if (key === 'topicId') result.topicId = value === null ? null : id(value);
    else if (key === 'kind') { assert(['note', 'sticky', 'text'].includes(value)); result.kind = value; }
    else if (key === 'width' || key === 'height') { assert(Number.isFinite(value) && value >= 12 && value <= 5000); result[key] = value; }
    else if (key === 'table') {
      assert(value && Array.isArray(value.columns) && value.columns.length >= 2 && value.columns.length <= 8 && Array.isArray(value.rows) && value.rows.length <= 40);
      result.table = { columns: value.columns.map(v => text(v, 100)), rows: value.rows.map(r => { assert(Array.isArray(r.cells) && r.cells.length === value.columns.length); return { label: text(r.label, 100), cells: r.cells.map(v => text(v, 2000)) }; }) };
    } else throw new Error('Unbekanntes Notizfeld');
  }
  return result;
}
module.exports = { ID, KINDS, ICONS, uid, clone, assert, id, text, point, node, patch, blankBoard, validBoard };
