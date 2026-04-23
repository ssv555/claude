import fs from "node:fs";
const main = "C:/Users/ssv55/.claude/projects/d--Data-Documents-Programming-Projects-WEB-VDole/90d82d50-b180-4e3a-a7df-aa1ff062b6e0.jsonl";
function sum(f) {
  const ls = fs.readFileSync(f, "utf-8").split("\n").filter(Boolean);
  let i = 0, cc = 0, cr = 0, o = 0, n = 0;
  for (const l of ls) {
    try {
      const j = JSON.parse(l);
      if (j.message && j.message.usage) {
        const u = j.message.usage;
        i += u.input_tokens || 0;
        cc += u.cache_creation_input_tokens || 0;
        cr += u.cache_read_input_tokens || 0;
        o += u.output_tokens || 0;
        n++;
      }
    } catch {}
  }
  return { messages: n, input: i, cache_create: cc, cache_read: cr, output: o, total: i + cc + cr + o };
}
const m = sum(main);
const subDir = main.replace(".jsonl", "") + "/subagents";
const subs = [];
try {
  const files = fs.readdirSync(subDir).filter((f) => f.endsWith(".jsonl"));
  for (const f of files) subs.push({ file: f, ...sum(subDir + "/" + f) });
} catch {}
const grand = { ...m };
for (const s of subs) {
  grand.input += s.input;
  grand.cache_create += s.cache_create;
  grand.cache_read += s.cache_read;
  grand.output += s.output;
  grand.total += s.total;
}
console.log(JSON.stringify({ main: m, subagents: subs, grand }));
