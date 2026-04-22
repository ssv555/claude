import type { Cue } from "./parse-vtt";

const NOISE_TAGS = [
  "music",
  "applause",
  "laughter",
  "crowd cheering",
  "silence",
  "аплодисменты",
  "смех",
  "музыка",
  "тишина",
  "аплодирует",
];

const NOISE_RE = new RegExp(
  `\\[(?:${NOISE_TAGS.join("|")})\\]|\\((?:${NOISE_TAGS.join("|")})\\)`,
  "gi",
);

export function cleanText(s: string): string {
  return s
    .replace(NOISE_RE, "")
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizeCues(cues: Cue[]): Cue[] {
  const cleaned: Cue[] = [];
  for (const c of cues) {
    const text = cleanText(c.text);
    if (!text) continue;
    cleaned.push({ start: c.start, end: c.end, text });
  }
  return dedupeRolling(cleaned);
}

function dedupeRolling(cues: Cue[]): Cue[] {
  if (cues.length < 2) return cues;
  const out: Cue[] = [cues[0]];
  for (let i = 1; i < cues.length; i++) {
    const prev = out[out.length - 1];
    const cur = cues[i];
    if (cur.text === prev.text) {
      prev.end = cur.end;
      continue;
    }
    if (prev.text.endsWith(cur.text) || cur.text.startsWith(prev.text)) {
      out[out.length - 1] = {
        start: prev.start,
        end: cur.end,
        text: cur.text.length >= prev.text.length ? cur.text : prev.text,
      };
      continue;
    }
    out.push(cur);
  }
  return out;
}

export function joinFullText(cues: Cue[]): string {
  return cues.map((c) => c.text).join(" ").replace(/\s+/g, " ").trim();
}
