---
name: youtube-url-extract
model: sonnet
description: Offline extraction of YouTube videoId, playlistId, and startSec from any string — URLs, arbitrary text, mixed content. Zero network, zero dependencies. Use when the task requires pulling a YouTube identifier from a user message, a pasted URL, a log line, a description field, or any text blob that may contain one or more YouTube links. Supports all current link shapes: youtu.be/*, youtube.com/watch, /shorts, /embed, /live, /v, plus m.youtube.com, music.youtube.com, and youtube-nocookie.com. Also parses list= and t=/start=/#t= (formats: 90, 90s, 1m30s, 1h2m3s). NOT for fetching video metadata, titles, or subtitles — those require separate tooling.
---

# youtube-url-extract

Offline YouTube URL parser. Given any string, returns `{ videoId, playlistId, startSec }`.

## Contract

```ts
type YouTubeRef = {
  videoId: string | null;     // 11 chars [A-Za-z0-9_-]
  playlistId: string | null;  // PL|UU|LL|FL|RD|OL prefix + 8+ chars
  startSec: number | null;    // seconds (from t=, start=, #t=)
};

parseYouTube(input: string): YouTubeRef      // first link only
parseYouTubeAll(input: string): YouTubeRef[] // every link, in order
```

Both return a stable shape. Missing fields are `null`. Non-matching input → all `null`.

## CLI

```bash
bun ~/.claude/skills/youtube-url-extract/parse.ts "<text or URL>"
bun ~/.claude/skills/youtube-url-extract/parse.ts --all "<text with multiple links>"
```

Prints JSON to stdout. Exits 0 even when nothing matched (null result is valid). Exits 2 only when no input argument was supplied.

## Programmatic use

Import directly — no build step, Bun runs TypeScript:

```ts
import { parseYouTube, parseYouTubeAll } from "~/.claude/skills/youtube-url-extract/parse";

parseYouTube("https://youtu.be/dQw4w9WgXcQ?t=90s");
// { videoId: "dQw4w9WgXcQ", playlistId: null, startSec: 90 }
```

## Scope

- Offline only. No network, no API keys.
- `videoId` is canonical 11-char ID. The parser never fetches, validates, or normalises against YouTube's actual catalog.
- A 12-char blob after `v=` yields the first 11 chars — matches YouTube's own behaviour.
- `playlistId` requires a known prefix; arbitrary `list=` values are rejected.

## When to delegate to another skill instead

- Need title / author / duration / thumbnails → use `yt-dlp` (or `youtube-subtitle-fetch`).
- Need subtitles / transcript → use `youtube-subtitle-fetch`.
- Need video/audio download or transcode → use a download-oriented skill or call `yt-dlp`/`ffmpeg` directly.
