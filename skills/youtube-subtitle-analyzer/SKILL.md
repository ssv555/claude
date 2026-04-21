---
name: youtube-subtitle-analyzer
description: Fetches and structures YouTube subtitles into clean JSON (videoId, language, source, title, channel, duration, chapters, chunks, fullText). Uses yt-dlp under the hood to pull manual or auto-generated subs plus video metadata and description, then strips noise tags ([music], [applause], [аплодисменты] …), merges rolling-window duplicates typical of YouTube ASR, extracts chapters from the description, and caches everything under ~/.cache/youtube-toolkit/<videoId>/. Use when the user wants to summarise, outline, transcribe, or "analyse by subtitles" a YouTube video, or asks "о чём это видео / сделай конспект / расшифруй ролик / дай тезисы" with a YouTube URL in context. Also works on a local .vtt / .srt file via --file. NOT for videos without subtitles (no STT here — that is a separate direct-video-analyzer skill) and NOT for video/audio download. Semantic analysis (TL;DR, topics, key theses) is performed by the caller on the returned JSON, not by this skill.
---

# youtube-subtitle-analyzer

Converts a YouTube URL (or a local subtitle file) into structured JSON ready for downstream summarisation. Offline-capable after first fetch (results are cached by `videoId`).

## Requirements

- `yt-dlp` binary. Path resolution order:
  1. `$YTDLP_PATH` env var.
  2. Default: `d:/Data/Documents/Programming/Projects/WEB/common/yt-dlp/yt-dlp.exe`.
- Optional: `$YT_SUB_CACHE_DIR` env var (default `~/.cache/youtube-toolkit/`).

## CLI

```bash
bun ~/.claude/skills/youtube-subtitle-analyzer/analyze.ts <youtube-url>
bun ~/.claude/skills/youtube-subtitle-analyzer/analyze.ts <youtube-url> --no-cache
bun ~/.claude/skills/youtube-subtitle-analyzer/analyze.ts --file <path.vtt|.srt>
```

Prints JSON to stdout. On cache hit returns instantly, network untouched.

## Output shape

```ts
type AnalyzeResult = {
  videoId: string;
  language: string;            // "ru", "en", "en-US", "unknown", ...
  source: "manual" | "auto" | "file";
  title: string | null;
  channel: string | null;
  duration: number | null;     // seconds
  chapters: { start: number; title: string }[];
  chunks:   { start: number; end: number; text: string }[];
  fullText: string;
};
```

`chapters` comes from the video description (requires monotonic timestamps starting at `00:00`); empty array if the author provided none. `chunks` is normalised — noise tags stripped, rolling-window duplicates merged.

## Pipeline

1. `parseYouTube(input)` → `videoId`.
2. Cache hit on `analyzed.json` → return it.
3. Else `yt-dlp --dump-json` → metadata; `yt-dlp --write-subs --write-auto-subs --sub-lang ru,en --convert-subs vtt` → VTT file.
4. Pick best available sub: manual > auto, `ru` > `en`.
5. `parseCues` (VTT/SRT) → `normalizeCues` → `joinFullText`.
6. `parseChapters(description)` → chapters.
7. Write `subs.vtt`, `description.txt`, `meta.json`, `analyzed.json` to cache.

## Caveats

- Videos with no subtitles (neither manual nor auto) throw a clear error. Use a direct-video analyzer (not part of this skill) for those.
- Chapter parsing is strict: the first timestamp must be `00:00`, and timestamps must be monotonic increasing. Otherwise `chapters = []`.
- Semantic work (outline, TL;DR, key theses, action items) is the caller's job. This skill only returns data.
- Integration tests against the live YouTube API are manual (sample run at step 2.10). The parser/normaliser/chapters/cache modules are covered by bun:test unit tests.
