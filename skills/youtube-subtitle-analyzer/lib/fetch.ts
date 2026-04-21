import { mkdirSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

export type SubsFetch = {
  vtt: string;
  language: string;
  source: "manual" | "auto";
  meta: YtDlpMeta;
};

export type YtDlpMeta = {
  id: string;
  title: string;
  description: string;
  duration: number;
  channel: string;
  upload_date: string;
  webpage_url: string;
};

const DEFAULT_YTDLP =
  "d:/Data/Documents/Programming/Projects/WEB/common/yt-dlp/yt-dlp.exe";

function ytdlpBin(): string {
  return process.env.YTDLP_PATH || DEFAULT_YTDLP;
}

async function runYtDlp(args: string[]): Promise<{ stdout: string; stderr: string }> {
  const proc = Bun.spawn([ytdlpBin(), ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  if (code !== 0) {
    throw new Error(`yt-dlp exit ${code}: ${stderr.trim() || stdout.trim()}`);
  }
  return { stdout, stderr };
}

function isRateLimited(msg: string): boolean {
  return /\b429\b|Too Many Requests/i.test(msg);
}

async function withRetry<T>(
  label: string,
  fn: () => Promise<T>,
  attempts = 3,
  baseDelayMs = 2000,
): Promise<T> {
  let lastErr: unknown;
  for (let i = 1; i <= attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[${label}] attempt ${i}/${attempts} failed: ${msg}`);
      if (i < attempts) {
        const rateLimited = isRateLimited(msg);
        const base = rateLimited ? 15000 : baseDelayMs;
        const delay = base * Math.pow(2, i - 1);
        if (rateLimited) {
          console.error(`[${label}] 429 detected — backing off ${delay}ms`);
        }
        await new Promise((r) => setTimeout(r, delay));
      }
    }
  }
  throw lastErr;
}

export async function fetchMeta(url: string): Promise<YtDlpMeta> {
  return withRetry("yt-dlp meta", async () => {
    const { stdout } = await runYtDlp(["--skip-download", "--dump-json", "--no-warnings", url]);
    const o = JSON.parse(stdout);
    return {
      id: o.id,
      title: o.title,
      description: o.description ?? "",
      duration: o.duration ?? 0,
      channel: o.channel ?? o.uploader ?? "",
      upload_date: o.upload_date ?? "",
      webpage_url: o.webpage_url ?? url,
    };
  });
}

async function fetchOneLang(url: string, lang: string, dir: string): Promise<boolean> {
  try {
    await withRetry(`yt-dlp subs[${lang}]`, () =>
      runYtDlp([
        "--skip-download",
        "--write-subs",
        "--write-auto-subs",
        "--sub-lang",
        lang,
        "--sub-format",
        "vtt/best",
        "--convert-subs",
        "vtt",
        "--no-warnings",
        "-o",
        join(dir, "%(id)s.%(ext)s"),
        url,
      ]),
    );
    return true;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[yt-dlp subs[${lang}]] giving up after retries: ${msg}`);
    return false;
  }
}

export async function fetchSubs(url: string, langs: string[] = ["ru", "en"]): Promise<SubsFetch> {
  const dir = join(tmpdir(), `yt-subs-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`);
  mkdirSync(dir, { recursive: true });

  try {
    const meta = await fetchMeta(url);

    const gotLangs: string[] = [];
    for (const lang of langs) {
      if (await fetchOneLang(url, lang, dir)) gotLangs.push(lang);
    }

    const files = readdirSync(dir).filter((f) => f.endsWith(".vtt"));
    if (files.length === 0) {
      throw new Error(
        `no subtitle files obtained — tried langs=[${langs.join(",")}], succeeded=[${gotLangs.join(",")}]`,
      );
    }

    const pick = pickSubFile(files, langs);
    const vtt = readFileSync(join(dir, pick.file), "utf-8");
    return { vtt, language: pick.lang, source: pick.auto ? "auto" : "manual", meta };
  } finally {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {}
  }
}

function pickSubFile(
  files: string[],
  langs: string[],
): { file: string; lang: string; auto: boolean } {
  for (const lang of langs) {
    const manual = files.find(
      (f) => f.includes(`.${lang}.`) && !f.includes(`.${lang}-auto.`) && !/-orig/.test(f),
    );
    if (manual) return { file: manual, lang, auto: false };
  }
  for (const lang of langs) {
    const auto = files.find((f) => f.includes(`.${lang}.`));
    if (auto) return { file: auto, lang, auto: true };
  }
  const first = files[0];
  const langMatch = first.match(/\.([a-z]{2,3}(?:-[A-Za-z]+)?)\.vtt$/);
  return { file: first, lang: langMatch?.[1] ?? "unknown", auto: true };
}
