import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseCues, detectFormat } from "../lib/parse-vtt";

const fixtureDir = resolve(import.meta.dir, "fixtures");
const vtt = readFileSync(resolve(fixtureDir, "sample.vtt"), "utf-8");
const srt = readFileSync(resolve(fixtureDir, "sample.srt"), "utf-8");

describe("detectFormat", () => {
  test("vtt header → vtt", () => {
    expect(detectFormat(vtt)).toBe("vtt");
  });
  test("srt content → srt", () => {
    expect(detectFormat(srt)).toBe("srt");
  });
});

describe("parseCues — VTT", () => {
  const cues = parseCues(vtt);

  test("five cues parsed", () => {
    expect(cues.length).toBe(5);
  });

  test("first cue timestamps (seconds)", () => {
    expect(cues[0].start).toBe(0);
    expect(cues[0].end).toBe(2.5);
    expect(cues[0].text).toBe("Hello and welcome to the show.");
  });

  test("inline <c> tags stripped", () => {
    expect(cues[1].text).toBe("Today we will talk about parsers.");
  });

  test("[music] is preserved at this layer (normalize strips it)", () => {
    expect(cues[2].text).toBe("[music]");
  });

  test("cue settings (align:start position:0%) ignored", () => {
    expect(cues[4].start).toBeCloseTo(60.12, 2);
    expect(cues[4].end).toBeCloseTo(63.45, 2);
    expect(cues[4].text).toBe("Second minute kicks in here.");
  });
});

describe("parseCues — SRT", () => {
  const cues = parseCues(srt);

  test("five cues parsed (comma decimal)", () => {
    expect(cues.length).toBe(5);
  });

  test("srt first cue parsed", () => {
    expect(cues[0].start).toBe(0);
    expect(cues[0].end).toBe(2.5);
    expect(cues[0].text).toBe("Hello and welcome to the show.");
  });

  test("srt 1m cue", () => {
    expect(cues[4].start).toBeCloseTo(60.12, 2);
    expect(cues[4].text).toBe("Second minute kicks in here.");
  });
});

describe("parseCues — edge cases", () => {
  test("empty string → []", () => {
    expect(parseCues("")).toEqual([]);
  });

  test("only WEBVTT header → []", () => {
    expect(parseCues("WEBVTT\n\n")).toEqual([]);
  });

  test("CRLF line endings handled", () => {
    const crlf = vtt.replace(/\n/g, "\r\n");
    expect(parseCues(crlf).length).toBe(5);
  });
});
