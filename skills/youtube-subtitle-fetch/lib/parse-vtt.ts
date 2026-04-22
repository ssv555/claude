export type Cue = {
  start: number;
  end: number;
  text: string;
};

const VTT_TIME = /(\d{1,2}):(\d{2}):(\d{2})[.,](\d{3})/;
const CUE_LINE =
  /^(\d{1,2}:\d{2}:\d{2}[.,]\d{3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[.,]\d{3})/;

function toSeconds(ts: string): number {
  const m = ts.match(VTT_TIME);
  if (!m) return NaN;
  return (
    parseInt(m[1], 10) * 3600 +
    parseInt(m[2], 10) * 60 +
    parseInt(m[3], 10) +
    parseInt(m[4], 10) / 1000
  );
}

function stripInlineTags(s: string): string {
  return s
    .replace(/<\d{1,2}:\d{2}:\d{2}[.,]\d{3}>/g, "")
    .replace(/<\/?[cibuv](?:\.[^>]*)?>/gi, "")
    .trim();
}

export function parseCues(content: string): Cue[] {
  const lines = content.replace(/\r\n?/g, "\n").split("\n");
  const cues: Cue[] = [];
  let i = 0;

  if (lines[0]?.startsWith("WEBVTT")) i = 1;

  while (i < lines.length) {
    const line = lines[i];
    const m = line?.match(CUE_LINE);
    if (!m) {
      i++;
      continue;
    }
    const start = toSeconds(m[1]);
    const end = toSeconds(m[2]);
    i++;
    const textLines: string[] = [];
    while (i < lines.length && lines[i].trim() !== "") {
      textLines.push(lines[i]);
      i++;
    }
    const text = stripInlineTags(textLines.join(" ").replace(/\s+/g, " "));
    if (!isNaN(start) && !isNaN(end) && text) {
      cues.push({ start, end, text });
    }
  }

  return cues;
}

export function detectFormat(content: string): "vtt" | "srt" {
  return /^WEBVTT/.test(content.trimStart()) ? "vtt" : "srt";
}
