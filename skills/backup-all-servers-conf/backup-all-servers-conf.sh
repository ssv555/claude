#!/usr/bin/env bash
# backup-all-servers-conf.sh — full config snapshot for all personal infra servers.
#
# Self-contained. Claude does NOT browse snapshots or read secrets — this script
# does everything end-to-end and prints only a metadata summary.
#
# Usage:
#   bash backup-all-servers-conf.sh                 # backup all servers
#   bash backup-all-servers-conf.sh amsterdam_grey  # backup one server (by alias)
#   INFRA_ROOT=/path bash backup-all-servers-conf.sh
#
# Output: snapshots into $INFRA_ROOT/servers/<alias>/snapshots/<DATE>_full-config/
#         + drift report vs previous snapshot (if any)

set -euo pipefail

# ============================================================================
# CONFIG — edit here when servers change
# ============================================================================

INFRA_ROOT="${INFRA_ROOT:-/d/Data/Backup/Ubuntu-Servers/INFRA}"
DATE="$(date +%F)"
TODAY_SNAP="${DATE}_full-config"

# Server registry — format: alias|ssh_host_alias
# ssh_host_alias must be configured in ~/.ssh/config with HostName/Port/User/IdentityFile.
# Quick check: `ssh <alias> 'echo OK; sudo -n true && echo sudo-OK'`
SERVERS=(
  "amsterdam_grey|amsterdam_grey_ssv"
  "moscow_my|moscow_my"
  "amsterdam_my|amsterdam_my"
  "vdole_pro_timeweb_moscow|vdole_pro_timeweb_moscow"
)

# Per-server include paths (whitespace-separated)
PATHS_amsterdam_grey="/etc/nginx /etc/iptables /etc/netplan /etc/cron.d /etc/letsencrypt /etc/sysctl.d /etc/fail2ban /etc/ssh/sshd_config /etc/ssh/sshd_config.d /etc/sudoers.d /etc/logrotate.d /etc/docker/daemon.json /etc/default/zramswap /etc/systemd/system /etc/systemd/journald.conf.d /etc/modules-load.d /etc/wg-easy.env /root/wg-easy /usr/local/bin/wg-easy-hidden-peer.sh /usr/local/etc/xray"

PATHS_moscow_my="/etc/nginx /etc/netplan /etc/cron.d /etc/letsencrypt /etc/sysctl.d /etc/fail2ban /etc/ssh/sshd_config /etc/ssh/sshd_config.d /etc/sudoers.d /etc/logrotate.d /etc/systemd/system /etc/systemd/journald.conf.d /etc/modules-load.d /etc/wireguard /etc/amnezia/amneziawg /usr/local/bin/awg-add-peer.sh /usr/local/bin/awg-backup-daily.sh /usr/local/bin/awg-postup.sh /usr/local/bin/awg-postdown.sh /usr/local/bin/check-ssl-certs.sh /usr/local/bin/monitor_moscow_bot.sh /usr/local/bin/moscow-relay-watch.sh /usr/local/bin/vdole-pro-relay.sh /usr/local/bin/vdole-tg-forward.sh /usr/local/bin/wg0-as13335.sh /root/awg-backups"

PATHS_amsterdam_my="/etc/nginx /etc/iptables /etc/netplan /etc/cron.d /etc/letsencrypt /etc/sysctl.d /etc/fail2ban /etc/ssh/sshd_config /etc/ssh/sshd_config.d /etc/sudoers.d /etc/logrotate.d /etc/systemd/system /etc/systemd/journald.conf.d /etc/modules-load.d /etc/wireguard /etc/prometheus /etc/x-ui /etc/default/zramswap"

PATHS_vdole_pro_timeweb_moscow="/etc/nginx /etc/netplan /etc/cron.d /etc/letsencrypt /etc/sysctl.d /etc/fail2ban /etc/ssh/sshd_config /etc/ssh/sshd_config.d /etc/sudoers.d /etc/logrotate.d /etc/systemd/system /etc/systemd/journald.conf.d /etc/modules-load.d /etc/postgresql/18/main/postgresql.conf /etc/postgresql/18/main/pg_hba.conf /etc/postgresql/18/main/pg_ident.conf /etc/default/zramswap"

# Common excludes (applied across all servers)
COMMON_EXCLUDES=(
  --exclude='/etc/letsencrypt/csr'
  --exclude='/etc/nginx/_backup_*'
  --exclude='/etc/nginx/*.bak*'
  --exclude='/etc/nginx/*.dpkg-old'
  --exclude='/etc/nginx/*~'
  --exclude='/etc/nginx/conf.d/*.bak*'
  --exclude='*.bak.*'
  --exclude='/usr/local/bin/bun'
  --exclude='/usr/local/bin/mtg'
  --exclude='/usr/local/bin/prometheus'
  --exclude='/usr/local/bin/prometheus_wireguard_exporter'
  --exclude='/usr/local/bin/promtool'
)

# ============================================================================
# Helpers
# ============================================================================

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

human() {
  # Convert bytes to human size
  local b="$1"
  awk -v b="$b" 'BEGIN { s="BKMGT"; for(i=1; b>=1024 && i<5; i++) b/=1024; printf "%.1f%s\n", b, substr(s,i,1) }'
}

pack_old_snapshots() {
  local alias="$1"
  local snaps_dir="$INFRA_ROOT/servers/$alias/snapshots"
  [[ -d "$snaps_dir" ]] || return 0
  local packed=0
  shopt -s nullglob
  for old in "$snaps_dir"/*_full-config/; do
    local name
    name="$(basename "$old")"
    [[ "$name" == "$TODAY_SNAP" ]] && continue
    local archive="$snaps_dir/${name}.tar.gz"
    if [[ ! -f "$archive" ]]; then
      # Pack whole folder into single .tar.gz at snapshots/ level
      if tar czf "$archive" -C "$snaps_dir" "$name" 2>/dev/null; then
        rm -rf "$old"
        packed=$((packed + 1))
      else
        err "[$alias] failed to pack $name — leaving folder as-is"
        rm -f "$archive" 2>/dev/null
      fi
    else
      # Archive already exists (manual or from earlier run) — just remove the unpacked folder
      rm -rf "$old"
      packed=$((packed + 1))
    fi
  done
  shopt -u nullglob
  if [[ $packed -gt 0 ]]; then
    log "[$alias] packed $packed previous snapshot(s) → single .tar.gz at snapshots/ level, folders removed"
  fi
}

# Extract files-index.txt from a previous snapshot (folder OR .tar.gz archive)
# Returns path to a temp file with the index contents, or empty string if not found.
extract_prev_index() {
  local alias="$1"
  local snaps_dir="$INFRA_ROOT/servers/$alias/snapshots"
  [[ -d "$snaps_dir" ]] || { echo ""; return; }

  # Look for most recent previous snapshot — either folder or archive (excluding today)
  local prev_archive prev_folder candidate
  prev_archive="$(ls -1 "$snaps_dir"/*_full-config.tar.gz 2>/dev/null | grep -v "/${TODAY_SNAP}.tar.gz$" | sort -r | head -1 || true)"
  prev_folder="$(ls -1d "$snaps_dir"/*_full-config 2>/dev/null | grep -v "/${TODAY_SNAP}\$" | sort -r | head -1 || true)"

  # Compare names to pick the most recent
  local archive_name folder_name pick=""
  archive_name="$(basename "${prev_archive:-}" .tar.gz)"
  folder_name="$(basename "${prev_folder:-}")"
  if [[ -n "$archive_name" && -n "$folder_name" ]]; then
    if [[ "$archive_name" > "$folder_name" ]]; then pick="archive"; else pick="folder"; fi
  elif [[ -n "$archive_name" ]]; then pick="archive"
  elif [[ -n "$folder_name" ]]; then pick="folder"
  fi

  if [[ "$pick" == "folder" ]]; then
    local idx="$prev_folder/state/files-index.txt"
    [[ -f "$idx" ]] && { cp "$idx" "$2"; echo "$folder_name"; return; }
  elif [[ "$pick" == "archive" ]]; then
    tar xzf "$prev_archive" -O "$archive_name/state/files-index.txt" > "$2" 2>/dev/null
    [[ -s "$2" ]] && { echo "${archive_name}.tar.gz"; return; }
  fi
  echo ""
}

generate_manifest_stub() {
  local alias="$1" userhost="$2" snap_dir="$3" drift="$4"
  local manifest="$snap_dir/manifest.md"
  [[ -f "$manifest" ]] && { log "[$alias] manifest.md already exists — not overwriting"; return 0; }

  local cnt_state cnt_configs size_configs size_total
  cnt_state="$(find "$snap_dir/state" -maxdepth 1 -type f 2>/dev/null | wc -l)"
  cnt_configs="$(wc -l < "$snap_dir/state/files-index.txt" 2>/dev/null || echo 0)"
  size_configs="$(du -sh "$snap_dir/configs" 2>/dev/null | awk '{print $1}')"
  size_total="$(du -sh "$snap_dir" 2>/dev/null | awk '{print $1}')"

  local top_dirs
  top_dirs="$(find "$snap_dir/configs" -maxdepth 2 -mindepth 1 -type d 2>/dev/null \
    | sed "s|$snap_dir/configs/||" | sort | head -25)"

  cat > "$manifest" <<MANIFEST
# Snapshot: $(basename "$snap_dir") — $alias

**Сервер:** $alias ($userhost)
**Создан:** $(date '+%Y-%m-%d %H:%M %Z')
**Тип:** Автоматический snapshot через \`/backup-all-servers-conf\`

## Размер и состав

\`\`\`
state/          $cnt_state files
configs/        $cnt_configs files, $size_configs
configs.tar.gz  bundled (для transfer / restore)
Total:          $size_total
\`\`\`

state/ содержит:
- \`ports.txt\` — \`ss -tlnp\` + \`-ulnp\`
- \`iptables.txt\` + \`ip6tables.txt\`
- \`services.txt\` — \`systemctl --running\` + timers
- \`docker.txt\`, \`os.txt\`, \`disk.txt\`, \`versions.txt\`
- \`files-index.txt\` — \`sha256\\tsize\\tmtime\\tpath\` для каждого файла в configs/

## Drift vs previous snapshot

$drift

## Top-level dirs в configs/

\`\`\`
$top_dirs
\`\`\`

## Server-specific нюансы

> *Этот раздел — авто-stub.* Допиши руками если есть что-то нестандартное:
> - Сервисы в Docker (где host-volume, что внутри контейнера)
> - Custom скрипты в \`/usr/local/bin/\` и их назначение
> - Отсутствующие стандартные паттерны (например: \`/etc/iptables/\` нет → правила создаются скриптами)
> - Связи с другими серверами (peer'ы WG, tunnels, backup pipeline)
> - Особые secret-файлы и где они лежат

## Восстановление (стандартное)

\`\`\`bash
cd configs && sudo cp -a etc /
# server-specific: cp -a root/<...>, cp -a usr/<...>
sudo systemctl daemon-reload
sudo systemctl restart nginx   # + другие relevant сервисы
sudo certbot certificates       # проверить LE валидным
sudo iptables-restore < state/iptables.txt   # если netfilter-persistent
\`\`\`

## Связано

- [../../README.md](../../README.md)
- [../../../../SNAPSHOTS-INDEX.md](../../../../SNAPSHOTS-INDEX.md)
MANIFEST
  log "[$alias] manifest.md stub generated (server-specific нюансы — допиши вручную)"
}

# Stats captured per server for final report (parallel arrays keyed by alias position)
declare -A STATS_FILES STATS_SIZE STATS_DRIFT STATS_DURATION

backup_server() {
  local alias="$1" ssh_host="$2"
  local start_ts="$(date +%s)"
  local paths_var="PATHS_${alias}"
  local paths="${!paths_var:-}"
  if [[ -z "$paths" ]]; then
    err "no PATHS_$alias defined in script — skipping"
    return 1
  fi

  log "=== $alias (ssh:$ssh_host) ==="

  # Pack previous snapshots: pack whole folder into .tar.gz, remove folder
  pack_old_snapshots "$alias"

  local snap_dir="$INFRA_ROOT/servers/$alias/snapshots/$TODAY_SNAP"
  mkdir -p "$snap_dir/state"

  local remote_tmp="/tmp/snap-${alias}-${DATE}"
  local exclude_args=""
  for e in "${COMMON_EXCLUDES[@]}"; do
    exclude_args="$exclude_args $e"
  done

  # ---- Remote: build snapshot tarball -----------------------------------
  log "[$alias] probing + building tarball on server..."
  if ! ssh -o ConnectTimeout=10 -o ServerAliveInterval=30 -o BatchMode=yes "$ssh_host" "bash -s" <<REMOTE
set -e
sudo rm -rf $remote_tmp
sudo mkdir -p $remote_tmp/state

(sudo ss -tlnp; echo '---UDP---'; sudo ss -ulnp) 2>/dev/null | sudo tee $remote_tmp/state/ports.txt > /dev/null
sudo iptables-save 2>/dev/null | sudo tee $remote_tmp/state/iptables.txt > /dev/null
sudo ip6tables-save 2>/dev/null | sudo tee $remote_tmp/state/ip6tables.txt > /dev/null
sudo systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print \$1}' | sudo tee $remote_tmp/state/services.txt > /dev/null
sudo systemctl list-timers --no-pager 2>/dev/null | sudo tee -a $remote_tmp/state/services.txt > /dev/null
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>&1 | sudo tee $remote_tmp/state/docker.txt > /dev/null
(uname -a; cat /etc/os-release | head -5; uptime; date; echo; ip -br a) | sudo tee $remote_tmp/state/os.txt > /dev/null
(df -h; echo '---mount---'; mount | grep -vE '^cgroup|^tmpfs|^proc|^sys') | sudo tee $remote_tmp/state/disk.txt > /dev/null
{
  echo '=== nginx ==='; nginx -v 2>&1 || echo 'n/a'
  echo '=== certbot ==='; certbot --version 2>&1 || echo 'n/a'
  echo '=== docker ==='; docker --version 2>&1 || echo 'n/a'
  echo '=== psql ==='; psql --version 2>&1 || echo 'n/a'
  echo '=== bun ==='; bun --version 2>&1 || echo 'n/a'
  echo '=== xray ==='; xray version 2>&1 | head -3 || echo 'n/a'
  echo '=== wg ==='; wg --version 2>&1 || echo 'n/a'
  echo '=== awg ==='; awg --version 2>&1 || echo 'n/a'
} | sudo tee $remote_tmp/state/versions.txt > /dev/null

sudo tar czhf $remote_tmp/configs.tar.gz \\
  --warning=no-file-changed --warning=no-file-removed \\
  $exclude_args \\
  $paths 2>/dev/null || true

cd /tmp && sudo tar czf snap-${alias}-${DATE}.tar.gz \$(basename $remote_tmp)/
sudo chown \$(whoami):\$(id -gn) snap-${alias}-${DATE}.tar.gz
stat -c '%s' /tmp/snap-${alias}-${DATE}.tar.gz
REMOTE
  then
    err "[$alias] remote SSH failed — skipping this server"
    return 1
  fi

  # ---- Download bundle --------------------------------------------------
  log "[$alias] downloading bundle..."
  local local_bundle="$snap_dir/.bundle.tar.gz"
  if ! scp -q "${ssh_host}:/tmp/snap-${alias}-${DATE}.tar.gz" "$local_bundle"; then
    err "[$alias] scp failed"
    return 1
  fi

  # ---- Extract locally --------------------------------------------------
  local tmpx
  tmpx="$(mktemp -d)"
  tar xzf "$local_bundle" -C "$tmpx"
  local extracted="$tmpx/$(basename "$remote_tmp")"

  cp "$extracted"/state/* "$snap_dir/state/" 2>/dev/null || true
  cp "$extracted"/configs.tar.gz "$snap_dir/configs.tar.gz"

  rm -rf "$snap_dir/configs"
  mkdir -p "$snap_dir/configs"
  tar xzf "$snap_dir/configs.tar.gz" -C "$snap_dir/configs" 2>/dev/null || true

  rm -rf "$tmpx" "$local_bundle"

  # ---- Generate files-index.txt (sha256 + size + mtime + path) ----------
  log "[$alias] indexing (sha256)..."
  (cd "$snap_dir/configs" && find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
    local hash size mtime
    hash="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
    size="$(stat -c '%s' "$f" 2>/dev/null)"
    mtime="$(stat -c '%y' "$f" 2>/dev/null | cut -c1-19 | tr ' ' 'T')"
    printf '%s\t%s\t%s\t%s\n' "$hash" "$size" "$mtime" "${f#./}"
  done) > "$snap_dir/state/files-index.txt"

  local cnt sz
  cnt="$(wc -l < "$snap_dir/state/files-index.txt")"
  sz="$(du -sh "$snap_dir" 2>/dev/null | awk '{print $1}')"
  STATS_FILES[$alias]="$cnt"
  STATS_SIZE[$alias]="$sz"
  log "[$alias] DONE: $cnt files, $sz total"

  # ---- Drift report vs previous snapshot --------------------------------
  local drift_report prev_idx_tmp prev_name
  prev_idx_tmp="$(mktemp)"
  prev_name="$(extract_prev_index "$alias" "$prev_idx_tmp")"
  if [[ -n "$prev_name" && -s "$prev_idx_tmp" ]]; then
    local added removed changed
    added="$(comm -13 <(awk -F'\t' '{print $4}' "$prev_idx_tmp" | sort) <(awk -F'\t' '{print $4}' "$snap_dir/state/files-index.txt" | sort) | wc -l)"
    removed="$(comm -23 <(awk -F'\t' '{print $4}' "$prev_idx_tmp" | sort) <(awk -F'\t' '{print $4}' "$snap_dir/state/files-index.txt" | sort) | wc -l)"
    changed="$(join -t $'\t' -j 1 -o 1.1,2.1 \
      <(awk -F'\t' '{print $4"\t"$1}' "$prev_idx_tmp" | sort) \
      <(awk -F'\t' '{print $4"\t"$1}' "$snap_dir/state/files-index.txt" | sort) \
      | awk -F'\t' '$1 != $2' | wc -l)"
    drift_report="vs \`$prev_name\`: **+$added new, -$removed removed, ~$changed changed**"
    STATS_DRIFT[$alias]="+${added} -${removed} ~${changed} (vs ${prev_name%.tar.gz})"
    log "[$alias] drift $drift_report"
  else
    drift_report="**baseline** — no previous snapshot to compare against"
    STATS_DRIFT[$alias]="baseline (no prev)"
    log "[$alias] $drift_report"
  fi
  rm -f "$prev_idx_tmp"

  STATS_DURATION[$alias]=$(( $(date +%s) - start_ts ))

  # ---- Generate manifest.md stub (only if not exists) -------------------
  generate_manifest_stub "$alias" "$ssh_host" "$snap_dir" "$drift_report"

  # ---- Cleanup remote ---------------------------------------------------
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_host" "sudo rm -rf $remote_tmp /tmp/snap-${alias}-${DATE}.tar.gz" 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================

log "INFRA root:     $INFRA_ROOT"
log "Snapshot date:  $TODAY_SNAP"
log ""

# Optional filter — single server alias
FILTER="${1:-}"
TARGET_SERVERS=()
if [[ -n "$FILTER" ]]; then
  for entry in "${SERVERS[@]}"; do
    IFS='|' read -r alias _ <<<"$entry"
    if [[ "$alias" == "$FILTER" ]]; then
      TARGET_SERVERS+=("$entry")
    fi
  done
  if [[ ${#TARGET_SERVERS[@]} -eq 0 ]]; then
    err "unknown server alias: $FILTER"
    err "known: $(printf '%s\n' "${SERVERS[@]}" | awk -F'|' '{print $1}' | tr '\n' ' ')"
    exit 2
  fi
else
  TARGET_SERVERS=("${SERVERS[@]}")
fi

mkdir -p "$INFRA_ROOT"
FAILED=()
SUCCEEDED=()
START_TS="$(date +%s)"

# `set +e` around the loop so failures in backup_server don't kill the whole run;
# we explicitly check rc and tally pass/fail.
set +e
for entry in "${TARGET_SERVERS[@]}"; do
  IFS='|' read -r alias ssh_host <<<"$entry"
  backup_server "$alias" "$ssh_host"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    SUCCEEDED+=("$alias")
  else
    FAILED+=("$alias")
  fi
  log ""
done
set -e

END_TS="$(date +%s)"
DUR=$((END_TS - START_TS))

printf '\n'
printf '╔════════════════════════════════════════════════════════════════════════════════╗\n'
printf '║                              FINAL REPORT                                      ║\n'
printf '╠════════════════════════════════════════════════════════════════════════════════╣\n'
printf '║ Snapshot date: %-64s ║\n' "$TODAY_SNAP"
printf '║ INFRA root:    %-64s ║\n' "$INFRA_ROOT"
printf '║ Total time:    %-64s ║\n' "${DUR}s"
printf '╠══════════════════════════════╦═══════╦═════════╦══════╦═══════════════════════╣\n'
printf '║ %-28s ║ %5s ║ %7s ║ %4s ║ %-21s ║\n' "Server" "Files" "Size" "Time" "Drift"
printf '╠══════════════════════════════╬═══════╬═════════╬══════╬═══════════════════════╣\n'
for entry in "${TARGET_SERVERS[@]}"; do
  IFS='|' read -r alias _ <<<"$entry"
  local_files="${STATS_FILES[$alias]:-—}"
  local_size="${STATS_SIZE[$alias]:-—}"
  local_dur="${STATS_DURATION[$alias]:-—}"
  local_drift="${STATS_DRIFT[$alias]:-FAILED}"
  # Truncate drift to fit column
  if [[ ${#local_drift} -gt 21 ]]; then
    local_drift="${local_drift:0:18}..."
  fi
  [[ "$local_dur" != "—" ]] && local_dur="${local_dur}s"
  printf '║ %-28s ║ %5s ║ %7s ║ %4s ║ %-21s ║\n' "$alias" "$local_files" "$local_size" "$local_dur" "$local_drift"
done
printf '╠══════════════════════════════╩═══════╩═════════╩══════╩═══════════════════════╣\n'
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '║ STATUS:        %-64s ║\n' "FAILED on ${#FAILED[@]}/${#TARGET_SERVERS[@]}: ${FAILED[*]}"
  printf '╚════════════════════════════════════════════════════════════════════════════════╝\n'
  exit 1
fi
printf '║ STATUS:        %-64s ║\n' "ALL CLEAN — ${#SUCCEEDED[@]}/${#TARGET_SERVERS[@]} succeeded"
printf '║ Next step:     %-64s ║\n' "svn st \"$INFRA_ROOT\""
printf '╚════════════════════════════════════════════════════════════════════════════════╝\n'
