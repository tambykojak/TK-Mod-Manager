#!/usr/bin/env bash
# Copies workspace addons into the WoW Forever AddOns folder.
# Usage:
#   ./wowf-addons-install.sh --all
#   ./wowf-addons-install.sh JunkMaste
#   ./wowf-addons-install.sh --update JunkMaste
#   ./wowf-addons-install.sh --update --all
#   ./wowf-addons-install.sh --what-if --all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ADDONS_DIR="$WORKSPACE_ROOT/Addons"
COMMON_DIR="$WORKSPACE_ROOT/Common"
LIBS_DIR="$WORKSPACE_ROOT/Libs"
ADDONS_PATH="${ADDONS_PATH:-/mnt/d/Battle.net/World of Warcraft/_forever_/Interface/AddOns}"
UPDATE=0
WHAT_IF=0
INSTALL_ALL=0
ADDON_NAME=""

usage() {
  cat <<'EOF'
Usage: wowf-addons-install.sh [options] <addon-name | --all>

Copies folders from workspace/Addons into the WoW Forever AddOns directory.
Pass an addon name to install only that addon, or --all to install every
addon. Copies workspace/Common/ to Common/ beside src/ and workspace/Libs/
to Libs/. Nothing in those folders is renamed. Common and Libs are never
installed as their own AddOns. Existing addons are skipped unless you
confirm (or pass --update).

Options:
  --all           Install all addons under workspace/Addons
  -u, --update    Automatically overwrite addons that already exist
  -n, --what-if   Preview copies/updates without changing anything
  -h, --help      Show this help
  --path PATH     Override the AddOns folder path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) INSTALL_ALL=1; shift ;;
    -u|--update) UPDATE=1; shift ;;
    -n|--what-if) WHAT_IF=1; shift ;;
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
      if [[ -n "$ADDON_NAME" ]]; then
        echo "Only one addon name is allowed (got '$ADDON_NAME' and '$1')" >&2
        exit 1
      fi
      ADDON_NAME="$1"
      shift
      ;;
  esac
done

if [[ $INSTALL_ALL -eq 1 && -n "$ADDON_NAME" ]]; then
  echo "Pass either an addon name or --all, not both." >&2
  usage >&2
  exit 1
fi

if [[ $INSTALL_ALL -eq 0 && -z "$ADDON_NAME" ]]; then
  echo "Addon name or --all is required." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$ADDONS_PATH" ]]; then
  echo "AddOns folder not found: $ADDONS_PATH" >&2
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
echo "Target:  $ADDONS_PATH"
echo "Addons:  ${#sources[@]}"
echo

installed=0
updated=0
skipped=0

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

for src in "${sources[@]}"; do
  name="$(basename "$src")"
  dest="$ADDONS_PATH/$name"

  if [[ ! -d "$dest" ]]; then
    if [[ $WHAT_IF -eq 1 ]]; then
      echo "[what-if] Install $name (+ Common)"
    else
      mkdir -p -- "$dest"
      copy_addon "$src" "$dest"
      vendor_shared "$dest"
      echo "Installed: $name"
    fi
    installed=$((installed + 1))
    continue
  fi

  # Already exists
  if [[ $UPDATE -eq 1 || $WHAT_IF -eq 1 ]]; then
    do_update=1
  else
    read -r -p "$name already exists. Update? [y/N] " answe
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      do_update=1
    else
      do_update=0
    fi
  fi

  if [[ $do_update -eq 1 ]]; then
    if [[ $WHAT_IF -eq 1 ]]; then
      echo "[what-if] Update $name (+ Common)"
    else
      copy_addon "$src" "$dest"
      vendor_shared "$dest"
      echo "Updated: $name"
    fi
    updated=$((updated + 1))
  else
    echo "Skipped: $name"
    skipped=$((skipped + 1))
  fi
done

echo
echo "Done. installed=$installed updated=$updated skipped=$skipped"
