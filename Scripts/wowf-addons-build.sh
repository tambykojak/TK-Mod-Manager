#!/usr/bin/env bash
# Builds workspace addons into Outputs/ ready to copy.
# Usage:
#   ./wowf-addons-build.sh JunkMaste
#   ./wowf-addons-build.sh --all
#   ./wowf-addons-build.sh --all --what-if
#   ./wowf-addons-build.sh --out /path/to/dir --all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ADDONS_DIR="$WORKSPACE_ROOT/Addons"
COMMON_DIR="$WORKSPACE_ROOT/Common"
LIBS_DIR="$WORKSPACE_ROOT/Libs"
OUTPUTS_DIR="$WORKSPACE_ROOT/Outputs"
WHAT_IF=0
BUILD_ALL=0
ADDON_NAME=""

usage() {
  cat <<'EOF'
Usage: wowf-addons-build.sh [options] <addon-name | --all>

Copies folders from workspace/Addons into Outputs/, then copies
workspace/Common/ to Common/ beside src/ and workspace/Libs/ to Libs/.
Nothing in those folders is renamed. Production builds force
WoWF.DevMode = false in Common/DevMode.lua. Pass an addon name to
build only that addon, or --all to wipe Outputs/ and build every addon.

Options:
  --all           Build all addons (wipes Outputs/ first)
  -n, --what-if   Preview builds without writing anything
  -h, --help      Show this help
  --out PATH      Override the Outputs folder path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) BUILD_ALL=1; shift ;;
    -n|--what-if) WHAT_IF=1; shift ;;
    --out)
      OUTPUTS_DIR="${2:?--out requires a value}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$ADDON_NAME" ]]; then
        echo "Only one addon name is allowed (got '$ADDON_NAME' and '$1')" >&2
        exit 1
      fi
      ADDON_NAME="$1"
      shift
      ;;
  esac
done

if [[ $BUILD_ALL -eq 1 && -n "$ADDON_NAME" ]]; then
  echo "Pass either an addon name or --all, not both." >&2
  usage >&2
  exit 1
fi

if [[ $BUILD_ALL -eq 0 && -z "$ADDON_NAME" ]]; then
  echo "Addon name or --all is required." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$SOURCE_ADDONS_DIR" ]]; then
  echo "Workspace Addons folder not found: $SOURCE_ADDONS_DIR" >&2
  exit 1
fi

if [[ -n "$ADDON_NAME" ]]; then
  src="$SOURCE_ADDONS_DIR/$ADDON_NAME"
  if [[ ! -d "$src" ]]; then
    echo "Addon not found: $src" >&2
    exit 1
  fi
  sources=("$src")
else
  mapfile -t sources < <(
    find "$SOURCE_ADDONS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort
  )
fi

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "No addon folders found in: $SOURCE_ADDONS_DIR"
  exit 0
fi

echo "Source:  $SOURCE_ADDONS_DIR"
echo "Common:  $COMMON_DIR"
echo "Libs:    $LIBS_DIR"
echo "Output:  $OUTPUTS_DIR"
echo "Addons:  ${#sources[@]}"
echo

# rsync 23/24 = partial / vanished files — common on /mnt races, not fatal.
rsync_safe() {
  local rc=0
  rsync "$@" || rc=$?
  if [[ $rc -eq 0 || $rc -eq 23 || $rc -eq 24 ]]; then
    return 0
  fi
  return "$rc"
}

copy_addon() {
  local src="$1"
  local dest="$2"
  # Keep vendored Libs/ and Common/ during sync — vendor_shared refreshes them.
  # Old renamed files (CommonDevMode.lua, CommonUI/) are not excluded, so
  # --delete removes them. Deleting Libs/ or Common/ here races WSL/rsync.
  if command -v rsync >/dev/null 2>&1; then
    rsync_safe -a --delete \
      --exclude '/Libs/' \
      --exclude '/Common/' \
      -- "$src"/ "$dest"/
  else
    mkdir -p -- "$dest"
    local keep=""
    keep="$(mktemp -d)"
    if [[ -d "$dest/Libs" ]]; then
      mv -- "$dest/Libs" "$keep/Libs"
    fi
    if [[ -d "$dest/Common" ]]; then
      mv -- "$dest/Common" "$keep/Common"
    fi
    find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a -- "$src"/. "$dest"/
    if [[ -d "$keep/Libs" ]]; then
      rm -rf -- "$dest/Libs"
      mv -- "$keep/Libs" "$dest/Libs"
    fi
    if [[ -d "$keep/Common" ]]; then
      rm -rf -- "$dest/Common"
      mv -- "$keep/Common" "$dest/Common"
    fi
    rm -rf -- "$keep"
  fi
}

# shellcheck source=wowf-vendor-common.sh
source "$SCRIPT_DIR/wowf-vendor-common.sh"

if [[ $BUILD_ALL -eq 1 ]]; then
  if [[ $WHAT_IF -eq 1 ]]; then
    echo "[what-if] Wipe $OUTPUTS_DIR"
  else
    mkdir -p -- "$OUTPUTS_DIR"
    find "$OUTPUTS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    echo "Wiped: $OUTPUTS_DIR"
  fi
fi

built=0

for src in "${sources[@]}"; do
  name="$(basename "$src")"
  dest="$OUTPUTS_DIR/$name"

  if [[ $WHAT_IF -eq 1 ]]; then
    echo "[what-if] Build $name (+ Common) -> $dest"
  else
    mkdir -p -- "$OUTPUTS_DIR"
    mkdir -p -- "$dest"
    copy_addon "$src" "$dest"
    vendor_shared "$dest" --production
    echo "Built: $name"
  fi
  built=$((built + 1))
done

echo
echo "Done. built=$built"
