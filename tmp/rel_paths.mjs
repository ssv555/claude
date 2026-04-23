import path from "node:path";
import fs from "node:fs";
const archiveDir = path.resolve("d:/Data/Documents/Programming/Projects/WEB/VDole/docs/archive/sessions");
const main = "C:/Users/ssv55/.claude/projects/d--Data-Documents-Programming-Projects-WEB-VDole/90d82d50-b180-4e3a-a7df-aa1ff062b6e0.jsonl";
const subDir = main.replace(/\.jsonl$/, "") + "/subagents";
const real = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
const rel = (p) => path.relative(archiveDir, real(p)).split(path.sep).join("/");
const out = { main: rel(main), subs: [] };
try {
  const files = fs.readdirSync(subDir).filter((f) => f.endsWith(".jsonl"));
  for (const f of files) out.subs.push({ name: f, path: rel(subDir + "/" + f) });
} catch {}
console.log(JSON.stringify(out));
