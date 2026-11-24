#!/usr/bin/env bash
# Watches workspace addons (plus Common and Libs) and builds + installs on change.
# Usage:
#   ./wowf-addons-dev.sh                       # watch every addon under Addons/
#   ./wowf-addons-dev.sh JunkMaster            # watch only the named addon(s)
#   ./wowf-addons-dev.sh JunkMaster WenDing --interval 0.5

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ADDONS_DIR="$WORKSPACE_ROOT/Addons"
COMMON_DIR="$WORKSPACE_ROOT/Common"
LIBS_DIR="$WORKSPACE_ROOT/Libs"
BUILD_SCRIPT="$SCRIPT_DIR/wowf-addons-build.sh"
INSTALL_SCRIPT="$SCRIPT_DIR/wowf-addons-install.sh"
ADDONS_PATH="${ADDONS_PATH:-/mnt/d/Battle.net/World of Warcraft/_forever_/Interface/AddOns}"
INTERVAL="1"
SKIP_INITIAL=0
REQUESTED=()

usage() {
  cat <<'EOF'
Usage: wowf-addons-dev.sh [addon-name ...] [options]

Watches workspace/Addons/<name> for each addon, plus workspace/Common and
workspace/Libs. With no names, every addon under Addons/ is watched.

When a change is found, only the addons it affects are rebuilt and installed
(build, then install --update). A change in Common or Libs affects every
watched addon. New addon folders are picked up while the watch runs.

Uses polling so edits from Windows/Cursor are detected on WSL-mounted paths.

Options:
  --interval SECONDS   Poll interval (default: 1)
  --skip-initial       Do not build/install once at startup
  --path PATH          Override the AddOns folder path
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      INTERVAL="${2:?--interval requires a value}"
      shift 2
      ;;
    --skip-initial) SKIP_INITIAL=1; shift ;;
    --path)
      ADDONS_PATH="${2:?--path requires a value}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      REQUESTED+=("$1")
      shift
      ;;
  esac
done

if [[ ! -d "$SOURCE_ADDONS_DIR" ]]; then
  echo "Workspace Addons folder not found: $SOURCE_ADDONS_DIR" >&2
  exit 1
fi

if [[ ! -f "$BUILD_SCRIPT" ]]; then
  echo "Build script not found: $BUILD_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
  echo "Install script not found: $INSTALL_SCRIPT" >&2
  exit 1
fi

for name in ${REQUESTED[@]+"${REQUESTED[@]}"}; do
  if [[ ! -d "$SOURCE_ADDONS_DIR/$name" ]]; then
    echo "Addon not found: $SOURCE_ADDONS_DIR/$name" >&2
    exit 1
  fi
done

# Names of the addons being watched right now. Rediscovered every poll when
# no names were given, so a new addon folder joins the watch without a restart.
current_addons() {
  if [[ ${#REQUESTED[@]} -gt 0 ]]; then
    printf '%s\n' "${REQUESTED[@]}"
  else
    find "$SOURCE_ADDONS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort
  fi
}

# Stable signature of every file path, mtime, and size under the given dirs.
tree_fingerprint() {
  {
    local dir
    for dir in "$@"; do
      if [[ -d "$dir" ]]; then
        find "$dir" -type f -printf '%p %T@ %s\n' 2>/dev/null
      fi
    done
  } | sort | md5sum | awk '{print $1}'
}

declare -A ADDON_FP=()
SHARED_FP=""
CHANGED=()

# One log line: timestamp, label (addon or "watch"), message.
event() {
  printf '%s  %-11s %s\n' "$(date '+%H:%M:%S')" "$1" "$2"
}

now_ms() {
  date '+%s%3N'
}

# Runs one build or install step. Its normal output is discarded; only a
# failing step prints its output, indented under the FAILED line.
run_step() {
  local name="$1" label="$2" out rc=0
  shift 2
  out="$("$@" 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    return 0
  fi
  event "$name" "FAILED $label (exit $rc)"
  if [[ -n "$out" ]]; then
    sed 's/^/    /' <<<"$out"
  fi
  return 1
}

add_changed() {
  local name="$1" existing
  for existing in ${CHANGED[@]+"${CHANGED[@]}"}; do
    [[ "$existing" == "$name" ]] && return 0
  done
  CHANGED+=("$name")
}

# Compares fingerprints with the last scan and records changed addons in
# CHANGED. A change in Common or Libs marks every watched addon.
scan_changes() {
  local shared shared_changed=0 name fp
  shared="$(tree_fingerprint "$COMMON_DIR" "$LIBS_DIR")"
  if [[ "$shared" != "$SHARED_FP" ]]; then
    shared_changed=1
    if [[ -n "$SHARED_FP" ]]; then
      event "Common/Libs" "changed, rebuilding every addon"
    fi
  fi
  SHARED_FP="$shared"

  local names=()
  mapfile -t names < <(current_addons)
  for name in ${names[@]+"${names[@]}"}; do
    fp="$(tree_fingerprint "$SOURCE_ADDONS_DIR/$name")"
    if [[ $shared_changed -eq 1 || "$fp" != "${ADDON_FP[$name]:-}" ]]; then
      add_changed "$name"
    fi
    ADDON_FP[$name]="$fp"
  done
}

build_one() {
  local name="$1" start end
  start="$(now_ms)"
  run_step "$name" build bash "$BUILD_SCRIPT" "$name" || return 0
  run_step "$name" install bash "$INSTALL_SCRIPT" --update --path "$ADDONS_PATH" "$name" || return 0
  end="$(now_ms)"
  event "$name" "installed in $((end - start)) ms"
}

print_header() {
  local names=() joined=""
  mapfile -t names < <(current_addons)
  printf -v joined '%s, ' ${names[@]+"${names[@]}"}
  joined="${joined%, }"
  printf 'Dev watch  every %ss  Ctrl+C to stop\n' "$INTERVAL"
  printf '  %-8s %s\n' "addons" "${#names[@]}: $joined"
  printf '  %-8s %s\n' "shared" "Common, Libs"
  printf '  %-8s %s\n\n' "target" "$ADDONS_PATH"
}

print_header

CHANGED=()
scan_changes
if [[ $SKIP_INITIAL -eq 0 ]]; then
  for name in ${CHANGED[@]+"${CHANGED[@]}"}; do
    build_one "$name"
  done
else
  event "watch" "skipped initial build"
fi

event "watch" "watching for changes"

while true; do
  sleep "$INTERVAL"
  CHANGED=()
  scan_changes
  if [[ ${#CHANGED[@]} -gt 0 ]]; then
    # Brief settle delay for editors that write multiple times quickly.
    sleep 0.2
    scan_changes
    for name in "${CHANGED[@]}"; do
      build_one "$name"
    done
  fi
done
