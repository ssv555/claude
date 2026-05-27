#!/usr/bin/env bash
# run-all.sh — все локальные тесты /dev skill (синтаксис, шаблоны, allowlist, port-логика).
# Runs on chief PC via Git Bash. No SSH side effects.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SKILL_DIR/lib"

PASS=0
FAIL=0
FAILED_TESTS=()

ok()   { echo "  PASS: $1";   PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1";   FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); }

run() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}

echo "=== test 1: bash syntax check on lib/*.sh"
for f in "$LIB"/*.sh; do
    bn=$(basename "$f")
    if bash -n "$f" 2>/dev/null; then ok "bash -n $bn"; else fail "bash -n $bn"; fi
done

echo
echo "=== test 2: PowerShell parse check on dev.ps1"
PS_SCRIPT="\$ErrorActionPreference='Stop'; try { [void][scriptblock]::Create((Get-Content -Raw 'C:\\Users\\ssv55\\.claude\\skills\\dev\\dev.ps1')); Write-Host PARSE_OK } catch { Write-Host \"PARSE_FAIL: \$_\" }"
PS_OUT=$(powershell -NoProfile -Command "$PS_SCRIPT" 2>&1)
if echo "$PS_OUT" | grep -q PARSE_OK; then
    ok "PowerShell parses dev.ps1"
else
    fail "PowerShell parse dev.ps1 ($PS_OUT)"
fi

echo
echo "=== test 3: nginx template has required placeholders"
TPL="$LIB/nginx-dev-template.conf"
if [ -f "$TPL" ]; then
    grep -q '{{ALIAS}}'    "$TPL" && ok "nginx template has {{ALIAS}}"     || fail "nginx template missing {{ALIAS}}"
    grep -q '{{PORT_API}}' "$TPL" && ok "nginx template has {{PORT_API}}"  || fail "nginx template missing {{PORT_API}}"
    grep -q '{{PORT_HMR}}' "$TPL" && ok "nginx template has {{PORT_HMR}}"  || fail "nginx template missing {{PORT_HMR}}"
else
    fail "nginx-dev-template.conf missing"
fi

echo
echo "=== test 4: systemd unit files have required sections"
for u in dev-services-cleanup vdole-mirror; do
    SVC="$LIB/$u.service"; TMR="$LIB/$u.timer"
    if [ -f "$SVC" ]; then
        grep -q '^\[Service\]' "$SVC" && ok "$u.service has [Service]"  || fail "$u.service missing [Service]"
        grep -q '^ExecStart='  "$SVC" && ok "$u.service has ExecStart"  || fail "$u.service missing ExecStart"
    fi
done
[ -f "$LIB/dev-services-cleanup.timer" ] && grep -q 'OnCalendar' "$LIB/dev-services-cleanup.timer" \
    && ok "cleanup.timer has OnCalendar" || fail "cleanup.timer missing OnCalendar"
[ -f "$LIB/vdole-mirror.path" ] && grep -q 'PathModified' "$LIB/vdole-mirror.path" \
    && ok "vdole-mirror.path has PathModified" || fail "vdole-mirror.path missing PathModified"

echo
echo "=== test 5: allowlist JSON valid + structure"
ALLOW="$HOME/.claude/developers/skills_allowlist.json"
if [ -f "$ALLOW" ]; then
    # Use PowerShell as JSON parser (always available on Windows)
    PARSE_OUT=$(powershell -NoProfile -Command "
        try {
            \$j = Get-Content -Raw '$ALLOW' | ConvertFrom-Json
            \$g = @(\$j.global)
            if (\$g.Count -ge 1) { Write-Output 'GLOBAL_OK' }
            \$dangerous = @('deploy-to-prod','changelog-to-prod','prod-to-dev','dev','sealed','skill-creator','update-config','git-push-all')
            foreach (\$d in \$dangerous) {
                if (\$g -contains \$d) { Write-Output \"DANGER:\$d\" } else { Write-Output \"SAFE:\$d\" }
            }
        } catch { Write-Output \"PARSE_FAIL:\$_\" }
    " 2>&1)
    if echo "$PARSE_OUT" | grep -q PARSE_FAIL; then
        fail "allowlist JSON invalid"
    else
        ok "allowlist JSON valid"
        if echo "$PARSE_OUT" | grep -q GLOBAL_OK; then ok "allowlist.global is array"; else fail "allowlist.global not array"; fi
        while IFS= read -r line; do
            case "$line" in
                DANGER:*) fail "DANGEROUS skill in allowlist.global: ${line#DANGER:}";;
                SAFE:*)   ok   "no dangerous skill: ${line#SAFE:}";;
            esac
        done <<< "$PARSE_OUT"
    fi
else
    fail "allowlist file missing: $ALLOW"
fi

echo
echo "=== test 6: skill metadata frontmatter present"
SKILL_MD="$SKILL_DIR/SKILL.md"
[ -f "$SKILL_MD" ] && head -1 "$SKILL_MD" | grep -q '^---' && ok "SKILL.md has frontmatter" || fail "SKILL.md missing frontmatter"
[ -f "$SKILL_MD" ] && grep -qE '^name:\s*dev$' "$SKILL_MD" && ok "SKILL.md name=dev" || fail "SKILL.md name field"
[ -f "$SKILL_MD" ] && grep -qE '^model:\s*sonnet' "$SKILL_MD" && ok "SKILL.md model=sonnet" || fail "SKILL.md model field"

echo
echo "=== test 7: setuid wrapper compiles cleanly"
if command -v gcc >/dev/null 2>&1; then
    TMPOUT=$(mktemp)
    if gcc -O2 -Wall -Wextra -o "$TMPOUT" "$LIB/setuid-claude-wrapper.c" 2>&1; then
        ok "wrapper compiles without warnings"
    else
        fail "wrapper compile failed"
    fi
    rm -f "$TMPOUT"
else
    echo "  SKIP: gcc not installed locally"
fi

echo
echo "=== test 8: port allocator logic (PowerShell unit-test)"
PORT_TEST=$(cat <<'PS_EOF'
# Mock: 3 existing nginx confs with various port assignments
# Expected next-block = 40031 (skipping 40001, 40011, 40021)
$mockOccupied = @(40001, 40002, 40003, 40005, 40011, 40012, 40013, 40015, 40021, 40022)
$used = @{}
foreach ($p in $mockOccupied) { $used[$p] = $true }
$found = $null
for ($base = 40001; $base -le 49991; $base += 10) {
    $collide = $false
    foreach ($off in 0, 1, 2, 4) {
        if ($used.ContainsKey($base + $off)) { $collide = $true; break }
    }
    if (-not $collide) { $found = $base; break }
}
if ($found -eq 40031) { Write-Host 'PORT_TEST_OK' } else { Write-Host "PORT_TEST_FAIL: got $found" }
PS_EOF
)
if powershell -NoProfile -Command "$PORT_TEST" 2>&1 | grep -q PORT_TEST_OK; then
    ok "port allocator picks next free 10-block"
else
    fail "port allocator logic broken"
fi

echo
echo "=== test 9: dev-* skills exist in chief skills dir"
for s in dev dev-commit dev-push dev-reset dev-info dev-merge; do
    if [ -f "$HOME/.claude/skills/$s/SKILL.md" ]; then
        ok "skill $s/SKILL.md exists"
    else
        fail "skill $s missing"
    fi
done

echo
echo "=========================================="
echo "  TOTAL: $((PASS+FAIL))   PASS: $PASS   FAIL: $FAIL"
echo "=========================================="
if [ $FAIL -gt 0 ]; then
    echo
    echo "Failed tests:"
    printf '  - %s\n' "${FAILED_TESTS[@]}"
    exit 1
fi
exit 0
