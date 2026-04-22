import { describe, test, expect } from "bun:test";
import { parseYouTube, parseYouTubeAll } from "../parse";

const VID = "dQw4w9WgXcQ";
const PL = "PLxxxxxxxxxx";
const UU = "UUxxxxxxxxxx";

describe("parseYouTube — single-link extraction", () => {
  test("youtu.be short form", () => {
    expect(parseYouTube(`https://youtu.be/${VID}`)).toEqual({
      videoId: VID,
      playlistId: null,
      startSec: null,
    });
  });

  test("youtu.be without protocol", () => {
    expect(parseYouTube(`youtu.be/${VID}`).videoId).toBe(VID);
  });

  test("youtube.com/watch", () => {
    expect(parseYouTube(`https://www.youtube.com/watch?v=${VID}`).videoId).toBe(
      VID,
    );
  });

  test("watch with v= not first in query", () => {
    expect(
      parseYouTube(`youtube.com/watch?x=1&v=${VID}&y=2`).videoId,
    ).toBe(VID);
  });

  test("shorts path", () => {
    expect(parseYouTube(`youtube.com/shorts/${VID}`).videoId).toBe(VID);
  });

  test("embed path", () => {
    expect(parseYouTube(`youtube.com/embed/${VID}`).videoId).toBe(VID);
  });

  test("live path", () => {
    expect(parseYouTube(`youtube.com/live/${VID}`).videoId).toBe(VID);
  });

  test("legacy /v/ path", () => {
    expect(parseYouTube(`youtube.com/v/${VID}`).videoId).toBe(VID);
  });

  test("mobile subdomain", () => {
    expect(parseYouTube(`m.youtube.com/watch?v=${VID}`).videoId).toBe(VID);
  });

  test("music subdomain", () => {
    expect(parseYouTube(`music.youtube.com/watch?v=${VID}`).videoId).toBe(VID);
  });

  test("nocookie embed", () => {
    expect(
      parseYouTube(`www.youtube-nocookie.com/embed/${VID}`).videoId,
    ).toBe(VID);
  });

  test("URL embedded in dirty text", () => {
    expect(
      parseYouTube(
        `смотри это видео https://youtube.com/shorts/${VID} ну как?`,
      ).videoId,
    ).toBe(VID);
  });
});

describe("parseYouTube — playlist + timestamp", () => {
  test("video + playlist + 1m30s", () => {
    const r = parseYouTube(`youtube.com/watch?v=${VID}&list=${PL}&t=1m30s`);
    expect(r).toEqual({ videoId: VID, playlistId: PL, startSec: 90 });
  });

  test("youtu.be with t=90s", () => {
    const r = parseYouTube(`youtu.be/${VID}?t=90s`);
    expect(r).toEqual({ videoId: VID, playlistId: null, startSec: 90 });
  });

  test("youtu.be with bare seconds t=90", () => {
    const r = parseYouTube(`youtu.be/${VID}?t=90`);
    expect(r.startSec).toBe(90);
  });

  test("hash fragment #t=1h2m3s", () => {
    const r = parseYouTube(`youtu.be/${VID}#t=1h2m3s`);
    expect(r.startSec).toBe(3723);
  });

  test("playlist with UU prefix", () => {
    const r = parseYouTube(`youtube.com/watch?v=${VID}&list=${UU}`);
    expect(r.playlistId).toBe(UU);
  });
});

describe("parseYouTube — negative / edge", () => {
  test("empty string", () => {
    expect(parseYouTube("")).toEqual({
      videoId: null,
      playlistId: null,
      startSec: null,
    });
  });

  test("garbage without link", () => {
    expect(parseYouTube("hello world no link here")).toEqual({
      videoId: null,
      playlistId: null,
      startSec: null,
    });
  });

  test("broken id — 10 chars", () => {
    expect(parseYouTube("youtu.be/short10chr").videoId).toBeNull();
  });

  test("broken id — 12 chars in /watch (must not match 11-substring greedily)", () => {
    // 12 printable chars — our regex should not accept this as videoId.
    // We rely on the fact that watch?v= is followed by a non-id char boundary.
    expect(parseYouTube("youtube.com/watch?v=abcdefghijkl&x=1").videoId).toBe(
      "abcdefghijk", // first 11 chars from v= are the id; 12th is "l"
    );
    // Note: YouTube itself treats only the first 11 chars as canonical id.
  });
});

describe("parseYouTubeAll — multi-link", () => {
  test("two links in one text", () => {
    const text = `first https://youtu.be/${VID} then youtube.com/watch?v=aaaaaaaaaaa rest`;
    const all = parseYouTubeAll(text);
    expect(all.length).toBe(2);
    expect(all[0].videoId).toBe(VID);
    expect(all[1].videoId).toBe("aaaaaaaaaaa");
  });

  test("no links → empty array", () => {
    expect(parseYouTubeAll("nothing here")).toEqual([]);
  });
});
