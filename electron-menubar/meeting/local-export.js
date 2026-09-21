'use strict';
const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const time = seconds => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
function textExport(meeting) {
  return `${meeting.index.title}\n${meeting.index.startTime}\n\n` + meeting.transcript.segments.map(s => `[${time(s.tStart)}] ${s.speaker}${s.uncertain ? ' (unsicher)' : ''}: ${s.text}`).join('\n');
}
function htmlExport(meeting) {
  const rows = meeting.transcript.segments.map(s => `<p id="segment-${escape(s.id || s.tStart)}"><b>${time(s.tStart)} · ${escape(s.speaker)}</b>${s.uncertain ? ' · Zuordnung unsicher' : ''}<br>${escape(s.text)}</p>`).join('');
  const sections = (meeting.summary?.sections || []).map(section => `<h2>${escape(section.title)}</h2>${(section.claims || []).map(claim => `<p>${escape(claim.text)}</p><blockquote>${claim.sources.map(s => `<a href="#segment-${escape(s.id)}">${time(s.tStart)}</a> ${escape(s.speaker)}: ${escape(s.text)}`).join('<br>')}</blockquote>`).join('')}${section.sources.map(s => `<p><a href="#segment-${escape(s.id)}">${time(s.tStart)}</a> ${escape(s.speaker)}: ${escape(s.text)}</p>`).join('')}`).join('');
  return `<!doctype html><html lang="de"><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><title>${escape(meeting.index.title)}</title><style>body{font:15px/1.55 system-ui;max-width:900px;margin:40px auto;padding:20px;color:#18212a}h1{line-height:1.2}p{break-inside:avoid}a{color:#154786}@media print{body{margin:0}}</style><h1>${escape(meeting.index.title)}</h1><p>${escape(meeting.index.startTime)}</p><h2>Gesprächsübersicht</h2><p>${escape(meeting.summary?.kurzzusammenfassung || 'Noch kein Bericht vorhanden.')}</p>${sections}<h2>Vollständiges Transkript</h2>${rows}</html>`;
}
module.exports = { textExport, htmlExport };
