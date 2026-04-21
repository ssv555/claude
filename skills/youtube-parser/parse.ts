export type YouTubeRef = {
  videoId: string | null;
  playlistId: string | null;
  startSec: number | null;
};

const EMPTY: YouTubeRef = { videoId: null, playlistId: null, startSec: null };

const YT_URL_RE =
  /(?:https?:\/\/)?(?:www\.|m\.|music\.)?(?:youtube\.com|youtube-nocookie\.com|youtu\.be)\/[^\s"'<>)]*/gi;

const PATH_ID_RE = /\/(?:shorts|embed|live|v)\/([A-Za-z0-9_-]{11})/;
const YOUTU_BE_RE = /youtu\.be\/([A-Za-z0-9_-]{11})/i;
const Q_VIDEO_RE = /(?:^|&)v=([A-Za-z0-9_-]{11})/;
const Q_LIST_RE = /(?:^|&)list=((?:PL|UU|LL|FL|RD|OL)[A-Za-z0-9_-]{8,})/;
const Q_TIME_RE = /(?:^|&)(?:t|start)=([^&]+)/;
const HASH_TIME_RE = /(?:^|&)t=([^&]+)/;

function parseDuration(s: string): number | null {
  if (/^\d+$/.test(s)) return parseInt(s, 10);
  if (/^\d+s$/.test(s)) return parseInt(s, 10);
  const m = s.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
  if (!m || (!m[1] && !m[2] && !m[3])) return null;
  const h = parseInt(m[1] ?? "0", 10);
  const mm = parseInt(m[2] ?? "0", 10);
  const ss = parseInt(m[3] ?? "0", 10);
  return h * 3600 + mm * 60 + ss;
}

function extractFromUrl(url: string): YouTubeRef {
  const [pathAndQuery, hash = ""] = url.split("#", 2);
  const [path, query = ""] = pathAndQuery.split("?", 2);

  let videoId: string | null = null;
  const pm = path.match(PATH_ID_RE);
  if (pm) videoId = pm[1];
  if (!videoId) {
    const ym = url.match(YOUTU_BE_RE);
    if (ym) videoId = ym[1];
  }
  if (!videoId) {
    const vm = query.match(Q_VIDEO_RE);
    if (vm) videoId = vm[1];
  }

  let playlistId: string | null = null;
  const lm = query.match(Q_LIST_RE);
  if (lm) playlistId = lm[1];

  let startSec: number | null = null;
  const tm = query.match(Q_TIME_RE);
  const hm = hash.match(HASH_TIME_RE);
  const raw = tm?.[1] ?? hm?.[1];
  if (raw) startSec = parseDuration(raw);

  return { videoId, playlistId, startSec };
}

export function parseYouTubeAll(input: string): YouTubeRef[] {
  if (!input) return [];
  const out: YouTubeRef[] = [];
  const matches = input.matchAll(YT_URL_RE);
  for (const m of matches) {
    const ref = extractFromUrl(m[0]);
    if (ref.videoId) out.push(ref);
  }
  return out;
}

export function parseYouTube(input: string): YouTubeRef {
  const all = parseYouTubeAll(input);
  return all[0] ?? { ...EMPTY };
}

if (import.meta.main) {
  const args = Bun.argv.slice(2);
  const all = args[0] === "--all";
  const input = (all ? args.slice(1) : args).join(" ");
  if (!input) {
    console.error(
      'usage: bun parse.ts [--all] "<text or URL>"\n' +
        "  prints JSON for parseYouTube, or array for --all",
    );
    process.exit(2);
  }
  const result = all ? parseYouTubeAll(input) : parseYouTube(input);
  console.log(JSON.stringify(result, null, 2));
}
