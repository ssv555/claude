import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type CacheKind = "subs.vtt" | "description.txt" | "meta.json" | "analyzed.json";

const ROOT =
  process.env.YT_SUB_CACHE_DIR || join(homedir(), ".cache", "youtube-toolkit");

function cacheDir(videoId: string): string {
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) {
    throw new Error(`invalid videoId: ${videoId}`);
  }
  const dir = join(ROOT, videoId);
  mkdirSync(dir, { recursive: true });
  return dir;
}

export function cachePath(videoId: string, kind: CacheKind): string {
  return join(cacheDir(videoId), kind);
}

export function cacheGet(videoId: string, kind: CacheKind): string | null {
  const p = cachePath(videoId, kind);
  return existsSync(p) ? readFileSync(p, "utf-8") : null;
}

export function cachePut(videoId: string, kind: CacheKind, data: string): string {
  const p = cachePath(videoId, kind);
  const tmp = `${p}.part`;
  writeFileSync(tmp, data, "utf-8");
  renameSync(tmp, p);
  return p;
}

export function cacheRoot(): string {
  return ROOT;
}
