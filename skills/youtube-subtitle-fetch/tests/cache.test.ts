import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const TMP = mkdtempSync(join(tmpdir(), "yt-cache-test-"));
process.env.YT_SUB_CACHE_DIR = TMP;

const cache = await import("../lib/cache");

afterAll(() => {
  rmSync(TMP, { recursive: true, force: true });
});

const VID = "dQw4w9WgXcQ";

describe("cache", () => {
  test("cacheRoot respects env override", () => {
    expect(cache.cacheRoot()).toBe(TMP);
  });

  test("put/get round-trip", () => {
    cache.cachePut(VID, "description.txt", "hello");
    expect(cache.cacheGet(VID, "description.txt")).toBe("hello");
  });

  test("get for missing key → null", () => {
    expect(cache.cacheGet(VID, "subs.vtt")).toBeNull();
  });

  test("atomic write — no .part file after put", () => {
    cache.cachePut(VID, "analyzed.json", '{"x":1}');
    const p = cache.cachePath(VID, "analyzed.json");
    expect(existsSync(p)).toBe(true);
    expect(existsSync(`${p}.part`)).toBe(false);
  });

  test("overwrite replaces content", () => {
    cache.cachePut(VID, "description.txt", "v1");
    cache.cachePut(VID, "description.txt", "v2");
    expect(cache.cacheGet(VID, "description.txt")).toBe("v2");
  });

  test("rejects invalid videoId", () => {
    expect(() => cache.cachePath("bad", "subs.vtt")).toThrow();
    expect(() => cache.cachePath("../etc/passwd", "subs.vtt")).toThrow();
  });
});
