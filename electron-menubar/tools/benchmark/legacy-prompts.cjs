// Eingefrorener P0-Vergleich: eingebaute Prompts aus v1.14.0.
const { getCustomAgentPrompt } = require('../../dictation/custom-agent-prompt');

function getPolishPrompt(text, language, flavor, customSettings = null) {
  // Handle custom agent settings
  if (flavor === 'custom' && customSettings) {
    return getCustomAgentPrompt(text, language, customSettings);
  }

  const flavorPrompts = {
    code: `Du polierst Sprachtranskriptionen eines Softwareentwicklers. Der Text wurde per Whisper transkribiert — Tech-Begriffe sind oft falsch geschrieben.

DEINE AUFGABE:
1. Entferne Füllwörter (ähm, äh, also, sozusagen, quasi, halt, ne, oder so), Wiederholungen, Versprecher
2. Korrigiere Grammatik und Satzbau — aber behalte den INHALT und die AUSSAGE exakt bei
3. Erkenne und korrigiere ALLE falsch transkribierten Tech-Begriffe aus der Softwareentwicklung

TECH-BEGRIFFE KORREKTUR (Whisper schreibt diese oft falsch):
- Frameworks/Libraries: React, Next.js, Vue, Angular, Svelte, Express, Django, Flask, Laravel, Rails, Spring Boot, FastAPI, Tailwind CSS, shadcn/ui, Prisma, Drizzle, tRPC, Zustand, Redux, Vite, Webpack, Turbopack
- Sprachen: TypeScript, JavaScript, Python, Rust, Go, Swift, Kotlin, C#, C++, PHP, Ruby, Dart, SQL
- Tools/Plattformen: GitHub, GitLab, Docker, Kubernetes, Vercel, Netlify, AWS, Supabase, Firebase, MongoDB, PostgreSQL, Redis, Elasticsearch, Terraform, Jenkins, CircleCI
- React-Begriffe: useState, useEffect, useRef, useMemo, useCallback, useContext, useReducer, JSX, TSX, Props, State, Hooks, Component, Provider, Context
- Allgemein: API, REST, GraphQL, WebSocket, OAuth, JWT, CORS, CRUD, CLI, IDE, npm, yarn, pnpm, Bun, Node.js, Deno, ESLint, Prettier, CI/CD, DevOps, Frontend, Backend, Fullstack, Middleware, Deployment, Repository, Branch, Merge, Pull Request, Commit, Endpoint, Payload, Middleware, Groq, LLM, GPT, Claude, Anthropic, OpenAI
- Wenn der Sprecher ein Wort ausspricht und danach buchstabiert oder korrigiert, verwende die korrigierte Version
- "Grog" oder "GROG" → Groq, "Lama" oder "Lava" → Llama, "shad cn" → shadcn, "use state" → useState, "type script" → TypeScript, "next js" → Next.js, "node js" → Node.js, "Hiku" oder "HICUM" → Haiku

DATEINAMEN:
- Setze @ vor Dateinamen: "datei punkt tsx" → @datei.tsx
- CamelCase beibehalten: @RecordingWidget.tsx
- GROSSBUCHSTABEN beibehalten: @ROADMAP.md

WICHTIG:
- Gib NUR den korrigierten Text zurück, KEINE Kommentare oder Erklärungen
- Ändere NICHT den Sinn oder füge eigene Inhalte hinzu
- Behalte den natürlichen Sprechstil bei, mache nur technische Korrekturen

TEXT:
${text}`,

    meeting: `Du polierst Sprachtranskriptionen von Meetings und Besprechungen. Erstelle daraus ein sauberes Protokoll.

DEINE AUFGABE:
1. Entferne Füllwörter (ähm, äh, also, sozusagen, quasi, halt, ne), Wiederholungen, Versprecher
2. Strukturiere den Inhalt als übersichtliche Stichpunkte
3. Erkenne und markiere Aufgaben, Entscheidungen und nächste Schritte

FORMATIERUNG:
- Personennamen korrekt: Max Müller (nicht max müller)
- Datum: "am fünfzehnten dezember" → am 15. Dezember
- Uhrzeit: "um vierzehn uhr" → um 14:00 Uhr
- E-Mail: "max at firma punkt de" → max@firma.de
- URLs: "www punkt beispiel punkt com" → www.beispiel.com
- Action Items mit → oder - [ ] markieren
- Mehrere Themen als separate Stichpunkte strukturieren

WICHTIG:
- Gib NUR das formatierte Protokoll zurück, KEINE Kommentare
- Behalte alle Fakten, Namen, Zahlen und Entscheidungen exakt bei
- Fasse NICHT zusammen — strukturiere nur

TEXT:
${text}`,

    plain: `Du polierst Sprachtranskriptionen. Säubere den Text grammatikalisch, ohne den Inhalt oder Stil zu verändern.

DEINE AUFGABE:
1. Entferne Füllwörter (ähm, äh, also, sozusagen, quasi, halt, ne, oder so), Wiederholungen, Versprecher
2. Korrigiere Grammatik, Satzbau, Interpunktion
3. Deutsche Rechtschreibung: Substantive groß, korrekter Satzanfang

GESPROCHENE SATZZEICHEN UMWANDELN:
- "Punkt" → .  "Komma" → ,  "Fragezeichen" → ?  "Ausrufezeichen" → !
- "neuer Absatz" oder "Absatz" → Zeilenumbruch

WICHTIG:
- Gib NUR den korrigierten Text zurück, KEINE Kommentare
- Minimale Eingriffe — behalte den natürlichen Sprachfluss bei
- Ändere NICHT den Inhalt, nur die Form

TEXT:
${text}`,
  };

  return flavorPrompts[flavor] || flavorPrompts.code;
}

module.exports = { getPolishPrompt };
