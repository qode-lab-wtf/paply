function getCustomAgentPrompt(text, language, settings) {
  // Special handling for Prompt Generator mode
  if (settings.isPromptGenerator) {
    return getPromptGeneratorPrompt(text, language, settings);
  }

  const toneDescriptions = {
    technical: 'technisch und präzise',
    formal: 'formell und professionell',
    casual: 'locker und umgangssprachlich',
    creative: 'kreativ und ausdrucksstark'
  };

  const formatDescriptions = {
    prose: 'als Fließtext',
    bullets: 'als Stichpunkte',
    markdown: 'mit Markdown-Formatierung',
    code: 'als Code-Kommentare oder technische Dokumentation'
  };

  const lengthDescriptions = {
    short: 'kurz und knapp',
    medium: 'ausgewogen',
    long: 'ausführlich und detailliert'
  };

  const tone = toneDescriptions[settings.tone] || 'neutral';
  const format = formatDescriptions[settings.format] || 'als Fließtext';
  const length = lengthDescriptions[settings.length] || 'ausgewogen';
  const creativity = settings.creativity || 50;
  const outputLang = settings.outputLang || 'same';
  const domain = settings.domain || 'general';
  const fillerWords = settings.fillerWords !== false; // Default: remove filler words

  let domainHint = '';
  if (domain && domain !== 'general') {
    const domainHints = {
      tech: 'Beachte Tech-Begriffe (APIs, Frameworks, Programmiersprachen)',
      business: 'Beachte Business-Terminologie und professionelle Ausdrucksweise',
      creative: 'Beachte kreative Freiheiten und expressive Sprache',
      academic: 'Beachte akademische Terminologie und wissenschaftlichen Stil'
    };
    domainHint = domainHints[domain] || '';
  }

  let outputLangHint = '';
  if (outputLang === 'en') {
    outputLangHint = '\n\nWICHTIG: Übersetze den finalen Text ins Englische!';
  } else if (outputLang === 'de') {
    outputLangHint = '\n\nWICHTIG: Übersetze den finalen Text ins Deutsche!';
  }

  const creativityHint = creativity > 70
    ? 'Sei kreativ: Verbessere Formulierungen, füge passende Ausdrücke hinzu.'
    : creativity < 30
      ? 'Sei minimal: Nur offensichtliche Fehler korrigieren, Originaltext maximal beibehalten.'
      : 'Sei ausgewogen: Korrigiere Fehler, behalte aber den Originalstil bei.';

  return `Du bist ein Transkriptions-Polierer für "${settings.name || 'Custom Agent'}".

EINGABESPRACHE: ${language}
TON: ${tone}
FORMAT: ${format}
LÄNGE: ${length}
KREATIVITÄT: ${creativity}% - ${creativityHint}
${domainHint}

REGELN:
${fillerWords ? '1. ENTFERNE: Füllwörter (ähm, äh, also, sozusagen, quasi, halt, ne, oder so), Wiederholungen, Versprecher' : '1. BEHALTE: Natürliche Sprachfluss, auch mit Füllwörtern'}
2. KORRIGIERE: Grammatik, Satzbau, Interpunktion
3. FORMATIERE: ${format}
4. ANPASSEN: Stil an "${tone}" anpassen

WICHTIG:
- Gib NUR den korrigierten Text zurück
- KEINE Kommentare, KEINE Erklärungen
- KEINE Interpretation was der User "meinen könnte"${outputLangHint}

TEXT:
${text}`;
}

// Special prompt for Prompt Generator mode (for Midjourney, DALL-E, etc.)
function getPromptGeneratorPrompt(text, language, settings) {
  const creativity = settings.creativity || 80;
  const outputLang = settings.outputLang || 'en';

  const creativityLevel = creativity > 70
    ? 'sehr detailliert und kreativ ausschmücken'
    : creativity > 40
      ? 'moderat erweitern und verbessern'
      : 'eng am Original bleiben, nur formattieren';

  return `Du bist ein Prompt-Generator für KI-Bildgenerierung (Midjourney, DALL-E, Stable Diffusion).

Deine Aufgabe: Wandle die gesprochene Beschreibung in einen professionellen, detaillierten Prompt um.

EINGABESPRACHE: ${language}
AUSGABESPRACHE: ${outputLang === 'en' ? 'Englisch' : outputLang === 'de' ? 'Deutsch' : 'wie Eingabe'}
KREATIVITÄT: ${creativity}% - ${creativityLevel}

PROMPT-STRUKTUR (folge dieser Reihenfolge):
1. Hauptmotiv/Subjekt - Was ist das zentrale Element?
2. Stil/Medium - Fotorealistisch, Illustration, 3D, Ölgemälde, etc.
3. Atmosphäre/Stimmung - Licht, Farben, Emotionen
4. Details - Texturen, Materialien, Umgebung
5. Technische Parameter - Kamerawinkel, Brennweite, Rendering-Qualität

WICHTIGE BEGRIFFE (nutze wenn passend):
- Qualität: masterpiece, highly detailed, 8k, ultra HD, professional
- Licht: golden hour, soft lighting, dramatic shadows, volumetric lighting
- Stil: cinematic, ethereal, minimalist, surreal, hyperrealistic
- Kamera: wide angle, close-up, bird's eye view, shallow depth of field

BEISPIEL-INPUT: "Ich möchte einen Astronauten der auf einem fremden Planeten steht und in die Ferne schaut"
BEISPIEL-OUTPUT: "Lone astronaut standing on alien planet surface, gazing at distant nebula, sci-fi concept art, volumetric lighting, cosmic atmosphere, detailed space suit with reflective visor, purple and orange alien landscape, dramatic composition, cinematic wide shot, 8k, highly detailed, masterpiece"

REGELN:
1. Entferne ALLE Füllwörter und Unsicherheiten
2. Extrahiere die Kernidee und erweitere sie professionell
3. Nutze passende technische Begriffe
4. Halte den Prompt zwischen 50-150 Wörtern
5. ${outputLang === 'en' ? 'Ausgabe MUSS auf Englisch sein' : outputLang === 'de' ? 'Ausgabe auf Deutsch' : 'Behalte die Sprache bei'}

WICHTIG:
- Gib NUR den fertigen Prompt zurück
- KEINE Erklärungen, KEINE Kommentare
- KEIN "Here is your prompt:" oder ähnliches

GESPROCHENE BESCHREIBUNG:
${text}`;
}

module.exports = { getCustomAgentPrompt };
