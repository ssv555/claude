import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseChapters } from "../lib/chapters";

const fixture = readFileSync(
  resolve(import.meta.dir, "fixtures/sample.description.txt"),
  "utf-8",
);

describe("parseChapters", () => {
  test("real-world description with mixed formats", () => {
    const chapters = parseChapters(fixture);
    expect(chapters).toEqual([
      { start: 0, title: "Intro" },
      { start: 90, title: "First topic" },
      { start: 342, title: "Deep dive into parsers" },
      { start: 3735, title: "Q&A" },
      { start: 4500, title: "Outro" },
    ]);
  });

  test("empty description → []", () => {
    expect(parseChapters("")).toEqual([]);
  });

  test("no timestamps → []", () => {
    expect(parseChapters("hello\nworld\nno chapters here")).toEqual([]);
  });

  test("first chapter must be 00:00 — otherwise []", () => {
    const d = "01:00 First\n02:00 Second";
    expect(parseChapters(d)).toEqual([]);
  });

  test("non-monotonic timestamps → []", () => {
    const d = "00:00 A\n02:00 B\n01:00 C";
    expect(parseChapters(d)).toEqual([]);
  });

  test("single chapter → [] (need ≥ 2)", () => {
    expect(parseChapters("00:00 Only")).toEqual([]);
  });

  test("hh:mm:ss format", () => {
    const d = "00:00 Start\n1:23:45 Late";
    expect(parseChapters(d)).toEqual([
      { start: 0, title: "Start" },
      { start: 5025, title: "Late" },
    ]);
  });
});
