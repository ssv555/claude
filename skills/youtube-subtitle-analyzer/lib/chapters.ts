export type Chapter = {
  start: number;
  title: string;
};

const TS_RE = /(?:(\d{1,2}):)?(\d{1,2}):(\d{2})/;
const CHAPTER_LINE_RE =
  /^\s*(?:[-•*]\s*)?(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\s*[-–—:.)]?\s*(.+?)\s*$/;

function toSeconds(h: string | undefined, m: string, s: string): number {
  return (h ? parseInt(h, 10) * 3600 : 0) + parseInt(m, 10) * 60 + parseInt(s, 10);
}

export function parseChapters(description: string): Chapter[] {
  if (!description) return [];
  const lines = description.replace(/\r\n?/g, "\n").split("\n");
  const raw: Chapter[] = [];

  for (const line of lines) {
    const m = line.match(CHAPTER_LINE_RE);
    if (!m) continue;
    const title = m[4].trim();
    if (!title) continue;
    if (!TS_RE.test(line)) continue;
    raw.push({ start: toSeconds(m[1], m[2], m[3]), title });
  }

  if (raw.length < 2) return [];
  if (raw[0].start !== 0) return [];

  const chapters: Chapter[] = [raw[0]];
  for (let i = 1; i < raw.length; i++) {
    if (raw[i].start <= chapters[chapters.length - 1].start) return [];
    chapters.push(raw[i]);
  }

  return chapters;
}
