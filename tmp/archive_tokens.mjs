import fs from 'fs';
const main = 'C:/Users/ssv55/.claude/projects/d--Data-Documents-Programming-Projects-WEB-VDole/680a938f-ad99-4555-87a9-fac19d3cdc56.jsonl';
const subDir = main.replace(/\.jsonl$/, '') + '/subagents';
function sum(f) {
  const ls = fs.readFileSync(f, 'utf-8').split('\n').filter(Boolean);
  let i = 0, cc = 0, cr = 0, o = 0, n = 0;
  for (const l of ls) {
    try {
      const j = JSON.parse(l);
      if (j.message?.usage) {
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
const subs = [];
try {
  const files = fs.readdirSync(subDir).filter(f => f.endsWith('.jsonl'));
  for (const f of files) subs.push({ file: f, ...sum(subDir + '/' + f) });
} catch {}
const grand = { input: m.input, cache_create: m.cache_create, cache_read: m.cache_read, output: m.output, total: m.total };
for (const s of subs) {
  grand.input += s.input;
  grand.cache_create += s.cache_create;
  grand.cache_read += s.cache_read;
  grand.output += s.output;
  grand.total += s.total;
}
console.log(JSON.stringify({ main: m, subagentCount: subs.length, grand }));
