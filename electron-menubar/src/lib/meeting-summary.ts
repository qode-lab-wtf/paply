// Normalisiert gespeicherte Berichte auf das v2-Schema, damit die Oberfläche nur EIN Format
// rendern muss. Alte v1-Berichte (kurzzusammenfassung/kernpunkte/todos/offeneFragen) werden
// verlustfrei abgebildet. Reine Funktion (getestet).
import type { MeetingSummary, MeetingTodo, SummaryV2 } from '@/types/meeting';

function str(v: unknown): string { return typeof v === 'string' ? v : ''; }

export function normalizeSummary(raw: MeetingSummary | null | undefined): SummaryV2 | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as unknown as Record<string, unknown>;
  const todos: MeetingTodo[] = (Array.isArray(r.todos) ? (r.todos as unknown[]) : []).map((t) => {
    const o = (t && typeof t === 'object' ? t : { text: String(t ?? '') }) as Record<string, unknown>;
    return {
      text: str(o.text),
      verantwortlich: str(o.verantwortlich) || null,
      frist: str(o.frist) || null,
      erledigt: !!o.erledigt,
    };
  }).filter((t) => t.text);
  const offeneFragen = (Array.isArray(r.offeneFragen) ? (r.offeneFragen as unknown[]) : []).map((q) => str(q)).filter(Boolean);

  if (r.schema === 2 || Array.isArray(r.themen)) {
    const themen = (Array.isArray(r.themen) ? (r.themen as unknown[]) : []).map((t) => {
      const o = (t && typeof t === 'object' ? t : { inhalt: String(t ?? '') }) as Record<string, unknown>;
      return { ueberschrift: str(o.ueberschrift), inhalt: str(o.inhalt) };
    }).filter((t) => t.inhalt || t.ueberschrift);
    const entscheidungen = (Array.isArray(r.entscheidungen) ? (r.entscheidungen as unknown[]) : []).map((e) => {
      const o = (e && typeof e === 'object' ? e : { text: String(e ?? '') }) as Record<string, unknown>;
      return { text: str(o.text), begruendung: str(o.begruendung) };
    }).filter((e) => e.text);
    const kurzfassung = str(r.kurzfassung) || str(r.kurzzusammenfassung);
    return {
      schema: 2,
      titel: str(r.titel) || kurzfassung.slice(0, 60),
      kurzfassung,
      themen,
      entscheidungen,
      offeneFragen,
      todos,
      generatedAt: str(r.generatedAt),
      model: str(r.model),
    };
  }

  // v1 → v2
  const kurz = str(r.kurzzusammenfassung);
  const kernpunkte = (Array.isArray(r.kernpunkte) ? (r.kernpunkte as unknown[]) : []).map((k) => str(k)).filter(Boolean);
  return {
    schema: 2,
    titel: kurz.slice(0, 60),
    kurzfassung: kurz,
    themen: kernpunkte.length ? [{ ueberschrift: 'Kernpunkte', inhalt: kernpunkte.map((k) => `• ${k}`).join('\n') }] : [],
    entscheidungen: [],
    offeneFragen,
    todos,
    generatedAt: str(r.generatedAt),
    model: str(r.model),
  };
}

function pad(n: number): string { return String(n).padStart(2, '0'); }
export function formatTime(sec: number): string {
  const s = Math.max(0, Math.floor(sec || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${pad(m)}:${pad(s % 60)}`;
}

/** Bericht + Konversation als Markdown (Export / Kopieren). */
export function summaryToMarkdown(
  title: string,
  summary: SummaryV2 | null,
  segments: { tStart: number; speaker: string; text: string }[],
  speakerLabel: (s: string) => string = (s) => s,
): string {
  const out: string[] = [`# ${title}`, ''];
  if (summary) {
    if (summary.kurzfassung) out.push(summary.kurzfassung, '');
    for (const t of summary.themen) { out.push(`## ${t.ueberschrift || 'Thema'}`, '', t.inhalt, ''); }
    if (summary.entscheidungen.length) {
      out.push('## Entscheidungen', '');
      for (const e of summary.entscheidungen) out.push(`- ${e.text}${e.begruendung ? ` — ${e.begruendung}` : ''}`);
      out.push('');
    }
    if (summary.offeneFragen.length) { out.push('## Offene Fragen', ''); for (const q of summary.offeneFragen) out.push(`- ${q}`); out.push(''); }
    if (summary.todos.length) {
      out.push('## To-dos', '');
      for (const t of summary.todos) out.push(`- [${t.erledigt ? 'x' : ' '}] ${t.text}${t.verantwortlich ? ` (${t.verantwortlich})` : ''}${t.frist ? ` – bis ${t.frist}` : ''}`);
      out.push('');
    }
  }
  if (segments.length) {
    out.push('## Konversation', '');
    for (const s of segments) out.push(`[${formatTime(s.tStart)}] **${speakerLabel(s.speaker)}:** ${s.text}`);
    out.push('');
  }
  return out.join('\n');
}
