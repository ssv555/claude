#!/usr/bin/env bash
# pre-receive — reject pushes to protected branches.
#
# Installed as /srv/git/VDole.git/hooks/pre-receive (exec 755).

set -euo pipefail

# Protected branch patterns (basename only — refs/heads/<X>)
PROTECTED=(main master prod production)
PROTECTED_GLOB='release/*'

reject() {
    printf '\n[VDole git] %s\n\n' "$1" >&2
    exit 1
}

# Chief (anyone NOT in 'developers' group) may push freely.
# Devs in 'developers' group are blocked from protected branches.
PUSHER="${GIT_PUSHER:-${USER:-}}"
if [ -n "$PUSHER" ] && ! id -nG "$PUSHER" 2>/dev/null | tr ' ' '\n' | grep -qx developers; then
    exit 0
fi

while read -r oldrev newrev refname; do
    # Only check branch refs
    case "$refname" in
        refs/heads/*) ;;
        *) continue ;;
    esac

    branch="${refname#refs/heads/}"

    for p in "${PROTECTED[@]}"; do
        if [ "$branch" = "$p" ]; then
            reject "Push to protected branch '$branch' is blocked. Open a PR on GitHub instead. (pusher: ${GIT_PUSHER:-$USER})"
        fi
    done

    # shellcheck disable=SC2053
    if [[ "$branch" == $PROTECTED_GLOB ]]; then
        reject "Push to protected branch '$branch' is blocked. Open a PR on GitHub instead."
    fi
done

exit 0
