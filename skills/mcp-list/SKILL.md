---
name: mcp-list
description: Show and toggle MCP servers
allowed-tools: Bash(node *), AskUserQuestion
model: haiku
fork: true
---

Manage MCP servers in `~/.claude.json` via `mcpList` (registry) and `mcpServers` (active).

IMPORTANT: All node commands below use SINGLE QUOTES for bash and DOUBLE QUOTES inside JS. Never use `!` operator — use `===0` or ternary instead (bash escapes `!`).

## Step 1: Show list

Run this node one-liner (Claude NEVER reads ~/.claude.json directly):

```bash
node -e 'const c=JSON.parse(require("fs").readFileSync(require("os").homedir()+"/.claude.json","utf8"));const list=c.mcpList||{};const active=c.mcpServers||{};const names=Object.keys(list);if(names.length===0){console.log("mcpList empty. Use init.")}else{console.log("# | Server | Status");names.forEach((n,i)=>console.log((i+1)+" | "+n+" | "+(active[n]?"on":"off")))}'
```

Display the output as a table. Add hint: `Commands: all on, all off, 1 3 on, 2 5 off, init`

## Step 2: Ask user

Use `AskUserQuestion` with options:
- `All on` — enable all servers
- `All off` — disable all servers
- `Done` — exit, no changes
- Other — user types: `1 on`, `2 3 off`, `init`

If user picks `Done` — stop, say nothing more.

## Step 3: Execute command

### init (first-time setup: copies mcpServers into mcpList)

```bash
node -e 'const p=require("os").homedir()+"/.claude.json";const c=JSON.parse(require("fs").readFileSync(p,"utf8"));c.mcpList={...(c.mcpList||{}),...(c.mcpServers||{})};require("fs").writeFileSync(p,JSON.stringify(c,null,2));console.log("init ok: "+Object.keys(c.mcpList).join(", "))'
```

### N on (copy from mcpList to mcpServers)

Replace `[INDICES]` with actual numbers from user input:

```bash
node -e 'const p=require("os").homedir()+"/.claude.json";const c=JSON.parse(require("fs").readFileSync(p,"utf8"));const names=Object.keys(c.mcpList||{});const idx=[INDICES];c.mcpServers=c.mcpServers||{};idx.forEach(i=>{const n=names[i-1];if(n){c.mcpServers[n]=c.mcpList[n];console.log(n+" -> on")}});require("fs").writeFileSync(p,JSON.stringify(c,null,2))'
```

### N off (remove from mcpServers)

```bash
node -e 'const p=require("os").homedir()+"/.claude.json";const c=JSON.parse(require("fs").readFileSync(p,"utf8"));const names=Object.keys(c.mcpList||{});const idx=[INDICES];idx.forEach(i=>{const n=names[i-1];if(n&&c.mcpServers){delete c.mcpServers[n];console.log(n+" -> off")}});if(c.mcpServers&&Object.keys(c.mcpServers).length===0)delete c.mcpServers;require("fs").writeFileSync(p,JSON.stringify(c,null,2))'
```

### all on

```bash
node -e 'const p=require("os").homedir()+"/.claude.json";const c=JSON.parse(require("fs").readFileSync(p,"utf8"));const list=c.mcpList||{};c.mcpServers={...(c.mcpServers||{}),...list};require("fs").writeFileSync(p,JSON.stringify(c,null,2));console.log("all on: "+Object.keys(list).join(", "))'
```

### all off

```bash
node -e 'const p=require("os").homedir()+"/.claude.json";const c=JSON.parse(require("fs").readFileSync(p,"utf8"));delete c.mcpServers;require("fs").writeFileSync(p,JSON.stringify(c,null,2));console.log("all off")'
```

## Step 4: Show updated list

After any toggle, re-run the Step 1 node one-liner and display the updated table.

Then say: **Restart IDE window to apply changes.**
