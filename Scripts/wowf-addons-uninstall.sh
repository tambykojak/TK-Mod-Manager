#!/usr/bin/env bash
# Uninstalls addons from the WoW Forever AddOns folder.
# Usage:
#   ./wowf-addons-uninstall.sh JunkMaste
#   ./wowf-addons-uninstall.sh --all
#   ./wowf-addons-uninstall.sh --all --what-if
#   ./wowf-addons-uninstall.sh --force --all

set -euo pipefail

ADDONS_PATH="${ADDONS_PATH:-/mnt/d/Battle.net/World of Warcraft/_forever_/Interface/AddOns}"
WHAT_IF=0
FORCE=0
UNINSTALL_ALL=0
ADDON_NAME=""

usage() {
  cat <<'EOF'
Usage: wowf-addons-uninstall.sh [options] <addon-name | --all>

Removes addons from the WoW Forever AddOns directory. Pass an addon name
to uninstall only that folder, or --all to remove everything under the
AddOns path.

Options:
  --all           Uninstall all items in the AddOns folde
  -n, --what-if   Preview deletions without removing anything
  -f, --force     Skip the confirmation prompt
  -h, --help      Show this help
  --path PATH     Override the AddOns folder path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) UNINSTALL_ALL=1; shift ;;
    -n|--what-if) WHAT_IF=1; shift ;;
    -f|--force) FORCE=1; shift ;;
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

if [[ $UNINSTALL_ALL -eq 1 && -n "$ADDON_NAME" ]]; then
  echo "Pass either an addon name or --all, not both." >&2
  usage >&2
  exit 1
fi

if [[ $UNINSTALL_ALL -eq 0 && -z "$ADDON_NAME" ]]; then
  echo "Addon name or --all is required." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$ADDONS_PATH" ]]; then
  echo "AddOns folder not found: $ADDONS_PATH" >&2
  exit 1
fi

if [[ -n "$ADDON_NAME" ]]; then
  target="$ADDONS_PATH/$ADDON_NAME"
  if [[ ! -e "$target" ]]; then
    echo "Addon not found: $target" >&2
    exit 1
  fi
  items=("$target")
else
  mapfile -t items < <(find "$ADDONS_PATH" -mindepth 1 -maxdepth 1 | sort)
fi

if [[ ${#items[@]} -eq 0 ]]; then
  echo "AddOns folder is already empty: $ADDONS_PATH"
  exit 0
fi

echo "Target: $ADDONS_PATH"
echo "Will remove ${#items[@]} item(s):"
for item in "${items[@]}"; do
  echo "  - $(basename "$item")"
done

if [[ $WHAT_IF -eq 1 ]]; then
  echo "WhatIf: no changes made."
  exit 0
fi

if [[ $FORCE -eq 0 ]]; then
  read -r -p "Delete the above? [y/N] " answe
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

for item in "${items[@]}"; do
  rm -rf -- "$item"
  echo "Removed: $(basename "$item")"
done

echo "Done."
