import { readFileSync } from "node:fs";
import { parseYouTube } from "../youtube-parser/parse";
import { fetchSubs, type YtDlpMeta } from "./lib/fetch";
import { parseCues, type Cue } from "./lib/parse-vtt";
import { normalizeCues, joinFullText } from "./lib/normalize";
import { parseChapters, type Chapter } from "./lib/chapters";
import { cacheGet, cachePut } from "./lib/cache";

export type AnalyzeResult = {
  videoId: string;
  language: string;
  source: "manual" | "auto" | "file";
  title: string | null;
  channel: string | null;
  duration: number | null;
  chapters: Chapter[];
  chunks: Cue[];
  fullText: string;
};

export type AnalyzeOptions = {
  langs?: string[];
  noCache?: boolean;
};

export async function analyze(url: string, opts: AnalyzeOptions = {}): Promise<AnalyzeResult> {
  const { videoId } = parseYouTube(url);
  if (!videoId) throw new Error(`no YouTube videoId found in: ${url}`);

  if (!opts.noCache) {
    const cached = cacheGet(videoId, "analyzed.json");
    if (cached) return JSON.parse(cached);
  }

  let vtt: string;
  let language: string;
  let source: "manual" | "auto";
  let meta: YtDlpMeta;

  const cachedSubs = opts.noCache ? null : cacheGet(videoId, "subs.vtt");
  const cachedMeta = opts.noCache ? null : cacheGet(videoId, "meta.json");

  if (cachedSubs && cachedMeta) {
    vtt = cachedSubs;
    meta = JSON.parse(cachedMeta);
    const header = vtt.match(/^NOTE source=(manual|auto) lang=([\w-]+)/m);
    source = (header?.[1] as "manual" | "auto") ?? "auto";
    language = header?.[2] ?? "unknown";
  } else {
    const fetched = await fetchSubs(url, opts.langs ?? ["ru", "en"]);
    vtt = `NOTE source=${fetched.source} lang=${fetched.language}\n\n${fetched.vtt}`;
    language = fetched.language;
    source = fetched.source;
    meta = fetched.meta;
    cachePut(videoId, "subs.vtt", vtt);
    cachePut(videoId, "description.txt", meta.description);
    cachePut(videoId, "meta.json", JSON.stringify(meta, null, 2));
  }

  const result = buildResult(videoId, language, source, meta, vtt);
  cachePut(videoId, "analyzed.json", JSON.stringify(result, null, 2));
  return result;
}

export function analyzeFile(path: string): AnalyzeResult {
  const content = readFileSync(path, "utf-8");
  return buildResult("local_file_", "unknown", "file", null, content);
}

function buildResult(
  videoId: string,
  language: string,
  source: "manual" | "auto" | "file",
  meta: YtDlpMeta | null,
  vtt: string,
): AnalyzeResult {
  const raw = parseCues(vtt);
  const chunks = normalizeCues(raw);
  const fullText = joinFullText(chunks);
  const chapters = meta?.description ? parseChapters(meta.description) : [];
  return {
    videoId,
    language,
    source,
    title: meta?.title ?? null,
    channel: meta?.channel ?? null,
    duration: meta?.duration ?? null,
    chapters,
    chunks,
    fullText,
  };
}

if (import.meta.main) {
  const args = Bun.argv.slice(2);
  const flags = new Set(args.filter((a) => a.startsWith("--")));
  const positional = args.filter((a) => !a.startsWith("--"));
  const fileIdx = args.indexOf("--file");
  const filePath = fileIdx >= 0 ? args[fileIdx + 1] : null;
  const noCache = flags.has("--no-cache");

  try {
    let result: AnalyzeResult;
    if (filePath) {
      result = analyzeFile(filePath);
    } else {
      const url = positional[0];
      if (!url) {
        console.error(
          'usage: bun analyze.ts <youtube-url> [--no-cache]\n' +
            '       bun analyze.ts --file <path.vtt|.srt>',
        );
        process.exit(2);
      }
      result = await analyze(url, { noCache });
    }
    console.log(JSON.stringify(result, null, 2));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`error: ${msg}`);
    process.exit(1);
  }
}
