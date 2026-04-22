import { describe, test, expect } from "bun:test";
import { cleanText, normalizeCues, joinFullText } from "../lib/normalize";
import type { Cue } from "../lib/parse-vtt";

describe("cleanText", () => {
  test("removes [music]", () => {
    expect(cleanText("hello [music] world")).toBe("hello world");
  });
  test("removes [аплодисменты]", () => {
    expect(cleanText("Спасибо [аплодисменты] всем")).toBe("Спасибо всем");
  });
  test("collapses whitespace", () => {
    expect(cleanText("  a\n\n  b   c  ")).toBe("a b c");
  });
  test("only-noise text → empty", () => {
    expect(cleanText("[music]")).toBe("");
  });
});

describe("normalizeCues", () => {
  test("drops noise-only cues", () => {
    const cues: Cue[] = [
      { start: 0, end: 1, text: "hello" },
      { start: 1, end: 2, text: "[music]" },
      { start: 2, end: 3, text: "world" },
    ];
    const out = normalizeCues(cues);
    expect(out.map((c) => c.text)).toEqual(["hello", "world"]);
  });

  test("merges identical adjacent cues (keeps outer start/end)", () => {
    const cues: Cue[] = [
      { start: 0, end: 1, text: "привет" },
      { start: 1, end: 2, text: "привет" },
      { start: 2, end: 3, text: "мир" },
    ];
    const out = normalizeCues(cues);
    expect(out.length).toBe(2);
    expect(out[0]).toEqual({ start: 0, end: 2, text: "привет" });
    expect(out[1].text).toBe("мир");
  });

  test("collapses rolling-window duplicates (prev is prefix of cur)", () => {
    const cues: Cue[] = [
      { start: 0, end: 2, text: "hello world" },
      { start: 1, end: 3, text: "hello world and you" },
    ];
    const out = normalizeCues(cues);
    expect(out.length).toBe(1);
    expect(out[0].text).toBe("hello world and you");
    expect(out[0].end).toBe(3);
  });
});

describe("joinFullText", () => {
  test("joins and trims", () => {
    const cues: Cue[] = [
      { start: 0, end: 1, text: "a" },
      { start: 1, end: 2, text: "b" },
      { start: 2, end: 3, text: "c" },
    ];
    expect(joinFullText(cues)).toBe("a b c");
  });
});
