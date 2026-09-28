#!/usr/bin/env bash
# Launch / inspect a dedicated Chrome debug profile (agent-agnostic).
# Independent from the daily Chrome profile — no need to quit daily Chrome.
set -euo pipefail

SOURCE_PROFILE="${CHROME_DEBUG_PROFILE:-$HOME/.chrome-debug-profile}"
PROFILE="$SOURCE_PROFILE"
PORT="${CHROME_DEBUG_PORT:-9222}"
CHROME_APP="${CHROME_APP:-/Applications/Google Chrome.app}"
CHROME_BIN="${CHROME_PATH:-$CHROME_APP/Contents/MacOS/Google Chrome}"
CDP="http://127.0.0.1:${PORT}"
PICK_PORT=0
CLONE_ID=""
CLONE_FROM=""
# 0 = do not steal desktop focus (macOS open -g); 1 = activate Chrome window
STEAL_FOCUS="${CHROME_DEBUG_STEAL_FOCUS:-0}"
# Legacy dir from older skill versions; cleaned by cleanup-clones
LEGACY_CLONE_BASE="${CHROME_DEBUG_CLONE_BASE:-$HOME/.chrome-debug-profile-clones}"
# Reuse daily (or custom) Chrome extensions via --load-extension (default on)
LOAD_EXTENSIONS="${CHROME_DEBUG_LOAD_EXTENSIONS:-1}"
EXTENSIONS_FROM="${CHROME_DEBUG_EXTENSIONS_FROM:-$HOME/Library/Application Support/Google/Chrome/Default/Extensions}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [flags]

Commands:
  status              Show port / CDP / profile state
  start               Start debug Chrome for source PROFILE
  clone-start         Copy source → \$SOURCE_PROFILE-<N>, pick free port, start
  list-clones         List numbered clone profiles (\$SOURCE_PROFILE-1, -2, ...)
  cleanup-clones      Stop+delete all numbered clones; keep source PROFILE only
  list-extensions     List extension dirs that would be loaded at start
  sync-extensions     Copy extension files from EXTENSIONS_FROM into source profile
  stop                Stop Chrome for current PROFILE (or --id <N> clone)
  reset-profile       stop + delete source PROFILE (asks for confirmation)
  doctor              Environment self-check

Clone dirs are siblings of the source, named with a numeric suffix:
  source:  ~/.chrome-debug-profile
  clones:  ~/.chrome-debug-profile-1
           ~/.chrome-debug-profile-2

Extensions:
  Independent profiles do NOT inherit daily Chrome extensions automatically.
  By default start/clone-start pass --load-extension pointing at the latest
  unpacked dirs under CHROME_DEBUG_EXTENSIONS_FROM (daily Chrome Default).

Env:
  CHROME_DEBUG_PROFILE          default: ~/.chrome-debug-profile  (source / primary)
  CHROME_DEBUG_PORT             default: 9222
  CHROME_APP                    default: /Applications/Google Chrome.app
  CHROME_PATH                   default: \$CHROME_APP/Contents/MacOS/Google Chrome
  CHROME_DEBUG_STEAL_FOCUS      default: 0 (keep current app focused); set 1 to activate Chrome
  CHROME_DEBUG_LOAD_EXTENSIONS  default: 1 (pass --load-extension); set 0 to disable
  CHROME_DEBUG_EXTENSIONS_FROM  default: ~/Library/Application Support/Google/Chrome/Default/Extensions

Flags:
  --pick-port         On start, if PORT is busy, scan PORT..PORT+30 for a free port
  --id <N>            clone-start: use this number (default: next free)
                      stop / list: target \$SOURCE_PROFILE-<N>
  --from <dir>        clone-start: source profile (default: CHROME_DEBUG_PROFILE)
                      sync-extensions: override Extensions source dir
EOF
}

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

sync_cdp() {
  CDP="http://127.0.0.1:${PORT}"
}

port_pids() {
  # lsof exits 1 when nothing listens — do not trip `set -e` / pipefail
  local out
  out="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    return 0
  fi
  awk 'NR>1 {print $2}' <<<"$out" | sort -u
}

port_busy() {
  [[ -n "$(port_pids || true)" ]]
}

cdp_ok() {
  curl -fsS --max-time 2 "$CDP/json/version" >/dev/null 2>&1
}

cdp_version_json() {
  curl -fsS --max-time 2 "$CDP/json/version" 2>/dev/null || true
}

cdp_list_json() {
  curl -fsS --max-time 2 "$CDP/json/list" 2>/dev/null || true
}

# True if a listening PID has open files under PROFILE
pid_uses_profile() {
  local pid="$1"
  local out
  out="$(lsof -nP -p "$pid" 2>/dev/null || true)"
  grep -F "$PROFILE" <<<"$out" >/dev/null 2>&1
}

our_debug_instance() {
  local pid
  local pids
  pids="$(port_pids || true)"
  [[ -z "$pids" ]] && return 1
  for pid in $pids; do
    if pid_uses_profile "$pid"; then
      return 0
    fi
  done
  return 1
}

find_free_port() {
  local start="${1:-$PORT}"
  local p
  for ((p=start; p<=start+30; p++)); do
    if ! lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      PORT="$p"
      sync_cdp
      return 0
    fi
  done
  return 1
}

# Prefer an unused port: try requested PORT first, else scan upward.
ensure_free_port() {
  if ! port_busy; then
    sync_cdp
    return 0
  fi
  local old="$PORT"
  if find_free_port "$PORT"; then
    if [[ "$PORT" != "$old" ]]; then
      log "Port $old busy; using free port $PORT"
    fi
    return 0
  fi
  err "No free port in range $old..$((old+30))"
  return 1
}

copy_profile() {
  local src="$1"
  local dest="$2"
  if [[ ! -d "$src" ]]; then
    err "Source profile does not exist: $src"
    err "Run: $0 start   # create/login on primary profile first"
    exit 1
  fi
  if [[ -e "$dest" ]]; then
    err "Clone destination already exists: $dest"
    err "Pick another --name, or remove it first."
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"

  # Source may still be running — skip Chrome singleton/lock files so the copy
  # can boot as a separate instance while keeping cookies/login data.
  log "Copying profile: $src → $dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='SingletonLock' \
      --exclude='SingletonCookie' \
      --exclude='SingletonSocket' \
      --exclude='lockfile' \
      --exclude='RunningChromeVersion' \
      --exclude='DevToolsActivePort' \
      --exclude='.DS_Store' \
      "$src/" "$dest/"
  else
    ditto "$src" "$dest"
    rm -f \
      "$dest/SingletonLock" \
      "$dest/SingletonCookie" \
      "$dest/SingletonSocket" \
      "$dest/lockfile" \
      "$dest/RunningChromeVersion" \
      "$dest/DevToolsActivePort" \
      2>/dev/null || true
  fi
  # Ensure no leftover lock from ditto race
  rm -f \
    "$dest/SingletonLock" \
    "$dest/SingletonCookie" \
    "$dest/SingletonSocket" \
    "$dest/lockfile" \
    "$dest/RunningChromeVersion" \
    "$dest/DevToolsActivePort" \
    2>/dev/null || true
  log "Copy done"
}

# Resolve latest unpacked version dir under each extension id.
# Prints absolute paths, one per line.
collect_extension_paths() {
  local root="${1:-$EXTENSIONS_FROM}"
  local id_dir ver_dir latest
  if [[ ! -d "$root" ]]; then
    return 0
  fi
  shopt -s nullglob
  for id_dir in "$root"/*/; do
    [[ -d "$id_dir" ]] || continue
    latest=""
    # Prefer newest mtime version folder (Chrome uses e.g. 7.0.18_0)
    for ver_dir in "$id_dir"*/; do
      [[ -d "$ver_dir" ]] || continue
      [[ -f "${ver_dir}manifest.json" ]] || continue
      if [[ -z "$latest" || "$ver_dir" -nt "$latest" ]]; then
        latest="$ver_dir"
      fi
    done
    if [[ -n "$latest" ]]; then
      # strip trailing slash
      printf '%s\n' "${latest%/}"
    fi
  done
  shopt -u nullglob
}

extension_load_arg() {
  local paths=()
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    paths+=("$p")
  done < <(collect_extension_paths "$EXTENSIONS_FROM")
  if [[ ${#paths[@]} -eq 0 ]]; then
    return 1
  fi
  local IFS=,
  printf '%s' "${paths[*]}"
  return 0
}

cmd_list_extensions() {
  log "EXTENSIONS_FROM=$EXTENSIONS_FROM"
  log "LOAD_EXTENSIONS=$LOAD_EXTENSIONS"
  local p name count=0
  if [[ ! -d "$EXTENSIONS_FROM" ]]; then
    log "(extensions source missing)"
    return 0
  fi
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    count=$((count + 1))
    name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$p/manifest.json" 2>/dev/null || echo '?')"
    log "ext=$p name=$name"
  done < <(collect_extension_paths "$EXTENSIONS_FROM")
  if [[ "$count" -eq 0 ]]; then
    log "(no loadable extensions found)"
  else
    log "ext_count=$count"
  fi
}

cmd_sync_extensions() {
  # Optional: copy extension files into the source debug profile so they also
  # exist on disk there. Enabling still relies on --load-extension at launch
  # (Secure Preferences HMAC prevents a simple enable-state copy).
  local src_root="${CLONE_FROM:-$EXTENSIONS_FROM}"
  # allow --from to override for this command via CLONE_FROM already parsed
  if [[ -n "${CLONE_FROM}" && "$CLONE_FROM" != "$SOURCE_PROFILE" ]]; then
    # if user passed a profile root instead of Extensions dir, accept both
    if [[ -d "$CLONE_FROM/Extensions" ]]; then
      src_root="$CLONE_FROM/Extensions"
    elif [[ -d "$CLONE_FROM/Default/Extensions" ]]; then
      src_root="$CLONE_FROM/Default/Extensions"
    else
      src_root="$CLONE_FROM"
    fi
  fi
  local dest_root="$SOURCE_PROFILE/Default/Extensions"
  if [[ ! -d "$src_root" ]]; then
    err "Extensions source not found: $src_root"
    exit 1
  fi
  # Prefer source profile not running hard locks on Extensions; warn only
  if pgrep -f -- "--user-data-dir=$SOURCE_PROFILE" >/dev/null 2>&1; then
    log "warning: source debug Chrome is running; copy may race. Prefer stop first."
  fi
  mkdir -p "$dest_root"
  log "Syncing extensions: $src_root → $dest_root"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src_root/" "$dest_root/"
  else
    rm -rf "$dest_root"
    mkdir -p "$dest_root"
    ditto "$src_root" "$dest_root"
  fi
  # Also copy extension storage if present next to Extensions
  local src_profile_default dest_default
  src_profile_default="$(dirname "$src_root")"
  dest_default="$SOURCE_PROFILE/Default"
  for sub in "Local Extension Settings" "Sync Extension Settings" "Extension State" "Extension Rules" "Extension Scripts"; do
    if [[ -d "$src_profile_default/$sub" ]]; then
      mkdir -p "$dest_default/$sub"
      if command -v rsync >/dev/null 2>&1; then
        rsync -a "$src_profile_default/$sub/" "$dest_default/$sub/"
      else
        ditto "$src_profile_default/$sub" "$dest_default/$sub"
      fi
      log "synced=$sub"
    fi
  done
  log "sync_extensions_done dest=$dest_root"
  log "note: start/clone-start still use --load-extension from EXTENSIONS_FROM (default daily). Set CHROME_DEBUG_EXTENSIONS_FROM=$dest_root to load from the synced copy."
}

launch_chrome() {
  if [[ ! -x "$CHROME_BIN" ]]; then
    err "Chrome not found at: $CHROME_BIN (set CHROME_PATH)"
    exit 1
  fi
  mkdir -p "$PROFILE"
  sync_cdp

  local chrome_args=(
    --remote-debugging-port="$PORT"
    --remote-debugging-address=127.0.0.1
    --user-data-dir="$PROFILE"
    --no-first-run
    --no-default-browser-check
    --disable-background-networking
  )

  if [[ "$LOAD_EXTENSIONS" == "1" ]]; then
    local load_arg
    if load_arg="$(extension_load_arg)"; then
      chrome_args+=(--load-extension="$load_arg")
      local n
      n="$(awk -F, '{print NF}' <<<"$load_arg")"
      log "load_extensions=$n from=$EXTENSIONS_FROM"
    else
      log "load_extensions=0 (none found under $EXTENSIONS_FROM)"
    fi
  else
    log "load_extensions=disabled (CHROME_DEBUG_LOAD_EXTENSIONS=$LOAD_EXTENSIONS)"
  fi

  chrome_args+=(about:blank)

  if [[ "$(uname -s)" == "Darwin" && -d "$CHROME_APP" ]]; then
    local open_flags=(-n)
    if [[ "$STEAL_FOCUS" != "1" ]]; then
      open_flags+=(-g)
      log "Launching in background (no focus steal). Set CHROME_DEBUG_STEAL_FOCUS=1 to activate."
    else
      log "Launching with focus (CHROME_DEBUG_STEAL_FOCUS=1)"
    fi
    open "${open_flags[@]}" -a "$CHROME_APP" --args "${chrome_args[@]}"
    log "Started via open(1) app=$CHROME_APP profile=$PROFILE port=$PORT"
  else
    nohup "$CHROME_BIN" "${chrome_args[@]}" >/dev/null 2>&1 &
    log "Started Chrome pid=$! profile=$PROFILE port=$PORT (direct; may steal focus)"
  fi

  local i
  for i in $(seq 1 20); do
    if cdp_ok; then
      log "CDP ready: $CDP"
      cmd_status
      return 0
    fi
    sleep 0.3
  done

  err "Chrome started but CDP not reachable at $CDP"
  err "Check: $0 status"
  exit 1
}

# Discover the remote-debugging port used by a live process for PROFILE.
discover_port_for_profile() {
  local pid port out
  local pids
  pids="$(pgrep -f -- "--user-data-dir=$PROFILE" 2>/dev/null || true)"
  [[ -z "$pids" ]] && return 1
  for pid in $pids; do
    out="$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null || true)"
    # Prefer 92xx-style debug ports if multiple listeners
    port="$(awk 'NR>1 {print $9}' <<<"$out" | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | sort -n | head -1)"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
      PORT="$port"
      sync_cdp
      return 0
    fi
  done
  return 1
}

clone_path_for_id() {
  printf '%s-%s' "$SOURCE_PROFILE" "$1"
}

# Emit absolute paths of numbered clones: $SOURCE_PROFILE-<digits>
iter_numbered_clone_paths() {
  local p base parent suffix
  base="$(basename "$SOURCE_PROFILE")"
  parent="$(dirname "$SOURCE_PROFILE")"
  shopt -s nullglob
  for p in "$parent/$base"-[0-9]*; do
    [[ -d "$p" ]] || continue
    suffix="${p#"$SOURCE_PROFILE-"}"
    [[ "$suffix" =~ ^[0-9]+$ ]] || continue
    printf '%s\n' "$p"
  done
  shopt -u nullglob
}

next_clone_id() {
  local p suffix max=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    suffix="${p#"$SOURCE_PROFILE-"}"
    if [[ "$suffix" =~ ^[0-9]+$ ]] && (( suffix > max )); then
      max=$suffix
    fi
  done < <(iter_numbered_clone_paths)
  echo $((max + 1))
}

resolve_clone_by_id() {
  if [[ -z "$CLONE_ID" ]]; then
    return 0
  fi
  if [[ ! "$CLONE_ID" =~ ^[0-9]+$ ]]; then
    err "--id must be a positive integer, got: $CLONE_ID"
    exit 1
  fi
  PROFILE="$(clone_path_for_id "$CLONE_ID")"
  if [[ ! -d "$PROFILE" ]]; then
    err "Clone not found: $PROFILE"
    exit 1
  fi
  if discover_port_for_profile; then
    return 0
  fi
  if [[ -f "$PROFILE/DevToolsActivePort" ]]; then
    local maybe
    maybe="$(tr -d '\r' <"$PROFILE/DevToolsActivePort" | sed -n '1p' || true)"
    if [[ "$maybe" =~ ^[0-9]+$ ]]; then
      PORT="$maybe"
      sync_cdp
    fi
  fi
}

stop_profile_dir() {
  local target="$1"
  local saved_profile="$PROFILE"
  local saved_port="$PORT"
  PROFILE="$target"
  discover_port_for_profile || true
  local extra
  extra="$(pgrep -f -- "--user-data-dir=$PROFILE" 2>/dev/null || true)"
  if [[ -n "$extra" ]]; then
    log "Stopping pids for $PROFILE: $extra"
    # shellcheck disable=SC2086
    kill $extra 2>/dev/null || true
  else
    log "No running Chrome for $PROFILE"
  fi
  PROFILE="$saved_profile"
  PORT="$saved_port"
  sync_cdp
}

cmd_status() {
  sync_cdp
  log "SOURCE_PROFILE=$SOURCE_PROFILE"
  log "PROFILE=$PROFILE"
  log "PORT=$PORT"
  log "CDP=$CDP"
  log "CHROME_APP=$CHROME_APP"
  log "CHROME_BIN=$CHROME_BIN"
  log "STEAL_FOCUS=$STEAL_FOCUS"
  log "LOAD_EXTENSIONS=$LOAD_EXTENSIONS"
  log "EXTENSIONS_FROM=$EXTENSIONS_FROM"

  if [[ ! -d "$CHROME_APP" ]]; then
    log "chrome_app: MISSING"
  else
    log "chrome_app: ok"
  fi
  if [[ ! -x "$CHROME_BIN" ]]; then
    log "chrome_bin: MISSING"
  else
    log "chrome_bin: ok"
  fi

  if [[ -d "$PROFILE" ]]; then
    log "profile_dir: exists"
  else
    log "profile_dir: not created yet (will be created on first start)"
  fi

  local pids
  pids="$(port_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)"
  if [[ -z "$pids" ]]; then
    log "port: free"
  else
    log "port: OCCUPIED pids=$pids"
    if our_debug_instance; then
      log "port_owner: this debug profile"
    else
      log "port_owner: OTHER process (do not assume it is your debug Chrome)"
    fi
  fi

  if cdp_ok; then
    log "cdp: ok"
    log "cdp_version: $(cdp_version_json | tr '\n' ' ')"
    local pages
    pages="$(cdp_list_json | python3 -c 'import sys,json
try:
  tabs=json.load(sys.stdin)
except Exception:
  print(0); raise SystemExit
print(sum(1 for t in tabs if t.get("type")=="page"))' 2>/dev/null || echo '?')"
    log "cdp_pages: $pages"
  else
    log "cdp: unreachable"
  fi
}

cmd_start() {
  PROFILE="$SOURCE_PROFILE"
  if port_busy; then
    if our_debug_instance && cdp_ok; then
      log "Already running for this profile on port $PORT"
      cmd_status
      return 0
    fi
    if [[ "$PICK_PORT" -eq 1 ]]; then
      local old="$PORT"
      if find_free_port "$PORT"; then
        log "Port $old busy; picked free port $PORT"
      else
        err "No free port in range $old..$((old+30))"
        exit 1
      fi
    else
      err "Port $PORT is occupied by another process."
      err "Run: $0 status"
      err "Or:  CHROME_DEBUG_PORT=<free> $0 start"
      err "Or:  $0 start --pick-port"
      err "Or:  $0 clone-start   # copy profile + new instance"
      exit 1
    fi
  fi
  launch_chrome
}

cmd_clone_start() {
  local src="${CLONE_FROM:-$SOURCE_PROFILE}"
  local id="$CLONE_ID"
  if [[ -z "$id" ]]; then
    id="$(next_clone_id)"
  elif [[ ! "$id" =~ ^[0-9]+$ ]]; then
    err "--id must be a positive integer, got: $id"
    exit 1
  fi

  local dest
  dest="$(clone_path_for_id "$id")"
  if [[ -e "$dest" ]]; then
    err "Clone already exists: $dest"
    err "Pick another --id, or run: $0 cleanup-clones"
    exit 1
  fi

  copy_profile "$src" "$dest"

  PROFILE="$dest"
  ensure_free_port
  launch_chrome

  log "clone_id=$id"
  log "clone_from=$src"
}

cmd_list_clones() {
  log "SOURCE_PROFILE=$SOURCE_PROFILE"
  local p id found=0 port_hint running
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    found=1
    id="${p#"$SOURCE_PROFILE-"}"
    port_hint="?"
    if [[ -f "$p/DevToolsActivePort" ]]; then
      port_hint="$(tr -d '\r' <"$p/DevToolsActivePort" | sed -n '1p' || echo '?')"
    fi
    running="no"
    if pgrep -f -- "--user-data-dir=$p" >/dev/null 2>&1; then
      running="yes"
    fi
    log "id=$id running=$running port_hint=$port_hint path=$p"
  done < <(iter_numbered_clone_paths | sort -V)
  # Also mention legacy clones dir if present
  if [[ -d "$LEGACY_CLONE_BASE" ]]; then
    local legacy_count
    legacy_count="$(find "$LEGACY_CLONE_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$legacy_count" != "0" ]]; then
      log "legacy_clones_dir=$LEGACY_CLONE_BASE count=$legacy_count (removed by cleanup-clones)"
      found=1
    fi
  fi
  if [[ "$found" -eq 0 ]]; then
    log "(no clones yet)"
  fi
}

remove_dir_retry() {
  local dir="$1"
  local i
  for i in 1 2 3 4 5; do
    if [[ ! -e "$dir" ]]; then
      return 0
    fi
    # Chrome may still hold files briefly after kill
    chmod -R u+w "$dir" 2>/dev/null || true
    if rm -rf "$dir" 2>/dev/null; then
      [[ ! -e "$dir" ]] && return 0
    fi
    sleep 0.4
  done
  if [[ -e "$dir" ]]; then
    err "Failed to remove: $dir (files may still be locked)"
    return 1
  fi
  return 0
}

cmd_cleanup_clones() {
  log "Cleaning clones; keeping source only: $SOURCE_PROFILE"
  local p removed=0 failed=0

  # Stop all first, then delete — reduces lock races
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    stop_profile_dir "$p"
  done < <(iter_numbered_clone_paths)
  if [[ -d "$LEGACY_CLONE_BASE" ]]; then
    local d
    shopt -s nullglob
    for d in "$LEGACY_CLONE_BASE"/*/; do
      [[ -d "$d" ]] || continue
      stop_profile_dir "${d%/}"
    done
    shopt -u nullglob
  fi
  sleep 0.6

  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if remove_dir_retry "$p"; then
      log "removed=$p"
      removed=$((removed + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(iter_numbered_clone_paths)

  if [[ -d "$LEGACY_CLONE_BASE" ]]; then
    local d
    shopt -s nullglob
    for d in "$LEGACY_CLONE_BASE"/*/; do
      [[ -d "$d" ]] || continue
      if remove_dir_retry "${d%/}"; then
        log "removed_legacy=${d%/}"
        removed=$((removed + 1))
      else
        failed=$((failed + 1))
      fi
    done
    shopt -u nullglob
    rmdir "$LEGACY_CLONE_BASE" 2>/dev/null || true
  fi

  log "cleanup_done removed=$removed failed=$failed source_kept=$SOURCE_PROFILE"
  if [[ "$failed" -gt 0 ]]; then
    exit 1
  fi
}

cmd_stop() {
  resolve_clone_by_id
  discover_port_for_profile || sync_cdp

  local stopped=0
  local extra
  extra="$(pgrep -f -- "--user-data-dir=$PROFILE" 2>/dev/null || true)"
  if [[ -n "$extra" ]]; then
    log "Stopping profile-matched pids: $extra (PROFILE=$PROFILE PORT=$PORT)"
    # shellcheck disable=SC2086
    kill $extra 2>/dev/null || true
    stopped=1
  else
    local pids pid
    pids="$(port_pids || true)"
    for pid in $pids; do
      [[ -z "$pid" ]] && continue
      if pid_uses_profile "$pid"; then
        log "Stopping pid=$pid (matches profile)"
        kill "$pid" 2>/dev/null || true
        stopped=1
      else
        log "Skip pid=$pid on port $PORT (different profile)"
      fi
    done
  fi
  if [[ "$stopped" -eq 0 ]]; then
    log "Nothing to stop for profile $PROFILE"
  else
    sleep 0.5
    cmd_status
  fi
}

cmd_reset_profile() {
  # Always target the source profile, never a numbered clone
  PROFILE="$SOURCE_PROFILE"
  log "This will STOP debug Chrome and DELETE source profile: $SOURCE_PROFILE"
  log "Numbered clones are NOT deleted; use cleanup-clones for those."
  if [[ "${CHROME_DEBUG_RESET_CONFIRM:-}" != "YES" ]]; then
    printf 'Type YES to confirm: '
    read -r ans
    if [[ "$ans" != "YES" ]]; then
      log "Aborted"
      exit 1
    fi
  fi
  cmd_stop || true
  rm -rf "$SOURCE_PROFILE"
  log "Profile removed: $SOURCE_PROFILE"
}

cmd_doctor() {
  cmd_status
  log "---"
  log "daily_chrome_note: keep daily Chrome open; this profile is isolated"
  log "clone_note: clone-start creates \$SOURCE_PROFILE-<N>; cleanup-clones keeps only source"
  log "extensions_note: start/clone-start load daily extensions via --load-extension (see list-extensions)"
  log "scope_note: this skill only opens Chrome; it does not configure MCP or run debugging"
  cmd_list_extensions
}

# Parse args
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

CMD="$1"
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pick-port) PICK_PORT=1 ;;
    --id)
      shift
      [[ $# -gt 0 ]] || { err "--id requires a value"; exit 1; }
      CLONE_ID="$1"
      ;;
    --name)
      # backward-compatible alias: treat as numeric id
      shift
      [[ $# -gt 0 ]] || { err "--name requires a numeric id"; exit 1; }
      CLONE_ID="$1"
      ;;
    --from)
      shift
      [[ $# -gt 0 ]] || { err "--from requires a value"; exit 1; }
      CLONE_FROM="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 1 ;;
  esac
  shift
done

case "$CMD" in
  status) cmd_status ;;
  start) cmd_start ;;
  clone-start) cmd_clone_start ;;
  list-clones) cmd_list_clones ;;
  cleanup-clones) cmd_cleanup_clones ;;
  list-extensions) cmd_list_extensions ;;
  sync-extensions) cmd_sync_extensions ;;
  stop) cmd_stop ;;
  reset-profile) cmd_reset_profile ;;
  doctor) cmd_doctor ;;
  -h|--help|help) usage ;;
  *) err "Unknown command: $CMD"; usage; exit 1 ;;
esac
