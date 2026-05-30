#!/usr/bin/env bash
# /opt/dev-skill/sync-skills-prune.sh — remove dirs in /opt/claude-shared/skills/
# that are NOT in the supplied allowlist. Called from dev.ps1 Sync-Skills.
#
# Usage: sudo bash sync-skills-prune.sh <space-separated allowlist names>
#
# Idempotent. Refuses to delete anything outside /opt/claude-shared/skills/.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "must run as root" >&2
    exit 1
fi

SKILLS_DIR='/opt/claude-shared/skills'
[ -d "$SKILLS_DIR" ] || exit 0

ALLOWED="${*:-}"
[ -n "$ALLOWED" ] || { echo "no allowlist supplied — aborting (safer than wiping)"; exit 2; }

for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    keep=0
    for a in $ALLOWED; do
        [ "$n" = "$a" ] && keep=1 && break
    done
    if [ $keep -eq 0 ]; then
        # Sanity: absolutely refuse anything that escaped /opt/claude-shared/skills/
        case "$d" in
            "$SKILLS_DIR"/*) ;;
            *) echo "[prune] refusing $d (outside skills dir)"; continue ;;
        esac
        echo "  [prune] $n"
        rm -rf "$d"
    fi
done
exit 0
