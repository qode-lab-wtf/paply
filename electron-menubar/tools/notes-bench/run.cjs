// Explicit, bounded synthetic quality probe. The key is read in memory from an
// app-settings file; never logged, copied into an artifact, or passed in argv.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createRepo } = require('../../notes/repo');
const { createLedger } = require('../../notes/ledger');
const { createGroq } = require('../../notes/groq');
const { splitSentences, context, validatePlan } = require('../../notes/plan');
const { blankBoard, uid, node } = require('../../notes/contracts');
const cases = [
  { name: 'Mindmap', text: 'Für unsere Auszeit im Frühjahr habe ich ein paar Gedanken. Ich möchte ans Meer. Ein kleines ruhiges Haus wäre schön. Wir sollten möglichst mit dem Zug hinkommen. Große Hotelanlagen mag ich nicht.', expected: 'mindmap' },
  { name: 'Vergleich', text: 'Ich vergleiche zwei Lampen für den Esstisch. Die Papierlampe kostet 80 Euro. Ihr Licht ist warm. Die Glaslampe kostet 140 Euro. Ihr Licht ist ebenfalls warm. Ob eine davon dimmbar ist, weiß ich noch nicht.', expected: 'table' },
  { name: 'Ablauf', text: 'Für das Testen von Paply zuerst den Hotkey drücken. Dann einen Gedanken einsprechen. Danach das Board öffnen und die neue Notiz prüfen. Zum Schluss eine Verbindung ziehen und schauen, ob sie an der Notiz bleibt.', expected: 'flow' },
  { name: 'Gemischte Gedanken', text: 'Für Paply wünsche ich mir ein ruhiges Notes-Board. Keine automatische Recherche. Ganz anderes Thema: Vielleicht fahren wir am Wochenende in den Wald. Zu Hause sollten wir noch die lose Schraube am Tisch festziehen.', expected: null },
];
async function main() {
  const args = process.argv.slice(2), configArg = args.indexOf('--config'), limitArg = args.indexOf('--limit');
  if (configArg < 0) { console.log(JSON.stringify({ mode: 'dry', cases: cases.length, note: 'Use --config <app settings file> for at most four synthetic live calls (18k token ceiling).' })); return; }
  const config = JSON.parse(fs.readFileSync(args[configArg + 1], 'utf8')); const key = config.groqApiKey;
  if (!key) throw new Error('No Groq key configured in the supplied app settings.');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-notes-bench-'));
  const repo = createRepo(root), ledger = createLedger(repo, () => ({ dailyTokens: 18000, dailyAudioMinutes: 1 }));
  const transport = [];
  const groq = createGroq({ getKey: () => key, ledger, fetchImpl: async (url, options) => {
    const reserved = repo.readLocal('ledger.json', []).at(-1)?.amount;
    const response = await fetch(url, options), data = await response.clone().json().catch(() => ({}));
    transport.push({ status: response.status, reserved, usage: data.usage, finishReason: data.choices?.[0]?.finish_reason }); return response;
  } });
  const limit = Math.max(1, Math.min(4, limitArg < 0 ? 4 : Number(args[limitArg + 1]) || 4));
  const large = args.includes('--large');
  const populated = args.includes('--populated'), board = blankBoard();
  if (populated) {
    for (let i = 0; i < 20; i++) { const id = uid('t'); board.topics[id] = { id, title: `Projekt ${i}: Küche, Garten und Alltag`, icon: 'home', owner: 'ai', createdAt: Date.now() }; }
    for (let i = 0; i < 30; i++) { const n = node({ kind: 'note', text: `Gedanke ${i}: Größe der Küche, Material, Ruhe und Licht beachten. Noch keine Entscheidung treffen.`, label: 'Küche und Zuhause', topicId: Object.keys(board.topics)[i % 20] }); board.nodes[n.id] = n; }
  }
  const inputs = populated ? [{ name: 'Befülltes Board mit echten IDs', text: 'Ich plane einen Küchengarten. Im Norden stehen die Tomaten. Im Süden wachsen Kräuter. Der Wasseranschluss liegt links. Für die Wege möchte ich Kies. Plastik möchte ich nicht verwenden. Die Bewässerung soll sparsam sein. Ein kleines Hochbeet wäre schön. Für die Erde kenne ich den Preis noch nicht. Der Zaun soll niedrig bleiben. Im Herbst möchte ich die Beete abdecken. Die sonnige Ecke soll frei bleiben.', expected: null }] : cases.slice(0, limit);
  const report = { at: new Date().toISOString(), model: large ? 'openai/gpt-oss-120b' : 'openai/gpt-oss-20b', populated, syntheticOnly: true, maxTokens: 18000, results: [], transport };
  for (const c of inputs) {
    const ctx = context(board, splitSentences(c.text, uid('s'))); let start = Date.now();
    try {
      let result;
      for (let attempt = 0; attempt < 2; attempt++) {
        try { result = await groq.plan(ctx, large); break; }
        catch (error) { if (attempt === 0 && ['budget', 'rate'].includes(error.kind) && error.retryMs < 65000) { await new Promise(resolve => setTimeout(resolve, error.retryMs)); start = Date.now(); } else throw error; }
      }
      const plan = validatePlan(result, ctx);
      const item = { name: c.name, valid: true, latencyMs: Date.now() - start, sentences: ctx.sentences.length, covered: plan.items.flatMap(i => i.sentenceIds).length, topics: plan.topics.map(t => t.title), structures: plan.structures.map(s => s.kind), expected: c.expected, usage: ledger.summary() };
      report.results.push(item); fs.writeFileSync(path.join(root, `${report.results.length}-plan.json`), JSON.stringify(plan, null, 2)); console.log(JSON.stringify(item));
    } catch (error) { const item = { name: c.name, valid: false, latencyMs: Date.now() - start, kind: error.kind || 'validation', message: error.message }; report.results.push(item); console.log(JSON.stringify(item)); if (['auth','key'].includes(error.kind)) break; }
    fs.writeFileSync(path.join(root, 'report.json'), JSON.stringify({ ...report, usage: ledger.summary() }, null, 2));
  }
  console.log(JSON.stringify({ report: path.join(root, 'report.json'), usage: ledger.summary() }));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
