---
name: .ps1 files ASCII-only
description: Write tool saves no-BOM, PS 5.x mangles Cyrillic
type: feedback
---

`.ps1` files: ASCII-only. No Cyrillic in comments or strings.

**Why:** Write saves UTF-8 no-BOM → PowerShell 5.x on RU Windows reads as CP1251 → Cyrillic → parser error `Unexpected token`. Recurring waste.

**Exception:** If Cyrillic unavoidable, add UTF-8 BOM after Write via `powershell -nop -c "$b=[IO.File]::ReadAllBytes('<f>.ps1'); if($b[0] -ne 0xEF){[IO.File]::WriteAllBytes('<f>.ps1',[byte[]]@(0xEF,0xBB,0xBF)+$b)}"`.

Companion: `.cmd`/`.bat` need CRLF (`unix2dos`) — already in global CLAUDE.md.
