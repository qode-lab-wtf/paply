import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

type Body = {
  transcription?: string;
  tone?: "Code" | "Casual" | "Formal";
  language?: "de" | "en";
  formatHint?: "default" | "bullets" | "code";
};

function cors(resp: NextResponse) {
  resp.headers.set("Access-Control-Allow-Origin", "*");
  resp.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  resp.headers.set("Access-Control-Allow-Headers", "*");
  return resp;
}

export async function OPTIONS() {
  return cors(new NextResponse(null, { status: 204 }));
}

const PROMPT_TEMPLATE = (
  raw: string,
  _tone: string,
  _lang: string,
  _formatHint: string,
) => `Du polierst Sprachtranskriptionen eines Softwareentwicklers. Der Text wurde per Whisper transkribiert — Tech-Begriffe sind oft falsch geschrieben.

DEINE AUFGABE:
1. Entferne Füllwörter (ähm, äh, also, sozusagen, quasi, halt, ne, oder so), Wiederholungen, Versprecher
2. Korrigiere Grammatik und Satzbau — aber behalte den INHALT und die AUSSAGE exakt bei
3. Erkenne und korrigiere ALLE falsch transkribierten Tech-Begriffe aus der Softwareentwicklung

TECH-BEGRIFFE KORREKTUR (Whisper schreibt diese oft falsch):
- Frameworks/Libraries: React, Next.js, Vue, Angular, Svelte, Tailwind CSS, shadcn/ui, Prisma, Zustand, Redux, Vite
- Sprachen: TypeScript, JavaScript, Python, Rust, Go
- Tools: GitHub, Docker, Kubernetes, Vercel, Supabase, Firebase, PostgreSQL, npm, Node.js
- React: useState, useEffect, useRef, useMemo, Props, Hooks, Component, JSX, TSX
- "Grog"/"GROG" → Groq, "Lama"/"Lava" → Llama, "shad cn" → shadcn, "use state" → useState, "type script" → TypeScript

WICHTIG:
- Gib NUR den korrigierten Text zurück, KEINE Kommentare oder Erklärungen
- Ändere NICHT den Sinn oder füge eigene Inhalte hinzu

TEXT:
${raw}`;

export async function POST(req: NextRequest) {
  const apiKey = process.env.GROQ_API_KEY;

  if (!apiKey) {
    return cors(
      NextResponse.json({ error: "GROQ_API_KEY fehlt" }, { status: 500 }),
    );
  }

  const body = (await req.json()) as Body;
  const raw = body.transcription?.trim() ?? "";
  const tone = body.tone ?? "Code";
  const lang = body.language ?? "de";
  const formatHint = body.formatHint ?? "default";

  if (!raw) {
    return cors(
      NextResponse.json({ error: "Keine Transkription" }, { status: 400 }),
    );
  }

  const payload = {
    model: "llama-3.3-70b-versatile",
    max_tokens: 1024,
    messages: [
      {
        role: "system",
        content: "Du bist ein Transkriptions-Polierer. Gib NUR den korrigierten Text zurück. Keine Kommentare, keine Erklärungen.",
      },
      {
        role: "user",
        content: PROMPT_TEMPLATE(raw, tone, lang, formatHint),
      },
    ],
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);

  try {
    const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (!res.ok) {
      const err = await res.text();
      console.error("Groq polish error", res.status, err);
      return cors(
        NextResponse.json(
          { error: `Polish fehlgeschlagen (${res.status})` },
          { status: 502 },
        ),
      );
    }

    const json = await res.json();
    const text = json?.choices?.[0]?.message?.content?.trim() || "";

    return cors(NextResponse.json({ text }));
  } catch (error) {
    clearTimeout(timeout);
    if (error instanceof Error && error.name === "AbortError") {
      console.error("Groq polish timeout");
      return cors(
        NextResponse.json({ error: "Timeout nach 30s" }, { status: 504 }),
      );
    }
    console.error(error);
    return cors(
      NextResponse.json({ error: "Polish failed" }, { status: 500 }),
    );
  }
}
