#!/usr/bin/env bash
# Shared Common + Libs → addon-root vendoring for install/build/dev.
#
# Contract:
#   - workspace/Common/** is copied as addon/Common/**. No renames.
#     Common sits beside src/ (Common/DevMode.lua, Common/UI/Core.lua).
#   - workspace/Libs/** is copied as addon/Libs/**. Filenames are never renamed.
#
# Usage (from install/build after setting COMMON_DIR and LIBS_DIR):
#   # shellcheck source=wowf-vendor-common.sh
#   source "$SCRIPT_DIR/wowf-vendor-common.sh"
#   vendor_shared "$dest"                 # install: keep DevMode=true
#   vendor_shared "$dest" --production    # build: force DevMode=false
#
# Expects: COMMON_DIR=workspace/Common, LIBS_DIR=workspace/Libs

# WSL/drvfs + Windows locks (game holding AddOn files open) break cp/mv overwrite
# and often block rm. Prefer truncating in place via redirect. Avoid cp -a: preserving
# times/ownership on /mnt/* frequently errors even after a successful content write.
copy_file_force() {
  local src="$1"
  local dest="$2"
  if cat -- "$src" > "$dest" 2>/dev/null; then
    return 0
  fi
  rm -f -- "$dest" 2>/dev/null || true
  cp -- "$src" "$dest"
}

# Drop the old renamed layout (CommonDevMode.lua, CommonUI/) so it cannot
# sit beside the real Common/ folder.
remove_prefixed_common() {
  local dest="$1"
  local d base

  shopt -s nullglob
  for d in "$dest"/Common*.lua; do
    rm -f -- "$d"
  done
  for d in "$dest"/Common*/; do
    base="$(basename "$d")"
    if [[ "$base" != "Common" ]]; then
      rm -rf -- "$d"
    fi
  done
  shopt -u nullglob
}

apply_production_devmode() {
  local dest="$1"
  local mode="${2:-}"

  if [[ "$mode" == "--production" && -f "$COMMON_DIR/DevMode.lua" ]]; then
    sed 's/WoWF\.DevMode = true/WoWF.DevMode = false/' \
      "$COMMON_DIR/DevMode.lua" > "$dest/Common/DevMode.lua"
  fi
}

vendor_common() {
  local dest="$1"
  local mode="${2:-}"
  local src rel dir out_dir out

  if [[ -z "${COMMON_DIR:-}" || ! -d "$COMMON_DIR" ]]; then
    return 0
  fi

  remove_prefixed_common "$dest"

  # Mirror Common/ → addon/Common/. rsync --delete drops files removed upstream.
  if command -v rsync >/dev/null 2>&1; then
    local rc=0
    mkdir -p -- "$dest/Common"
    rsync -a --delete -- "$COMMON_DIR"/ "$dest/Common"/ || rc=$?
    if [[ $rc -eq 0 || $rc -eq 23 || $rc -eq 24 ]]; then
      apply_production_devmode "$dest" "$mode"
      return 0
    fi
    echo "vendor_common: rsync failed (exit $rc); falling back to copy" >&2
  fi

  while IFS= read -r -d '' src; do
    rel="${src#"$COMMON_DIR"/}"
    rel="${rel//\\//}"
    dir="$(dirname "$rel")"

    if [[ "$dir" == "." ]]; then
      out_dir="$dest/Common"
    else
      out_dir="$dest/Common/$dir"
    fi
    out="$out_dir/$(basename "$rel")"

    mkdir -p -- "$out_dir"
    if [[ "$mode" == "--production" && "$rel" == "DevMode.lua" ]]; then
      sed 's/WoWF\.DevMode = true/WoWF.DevMode = false/' "$src" > "$out"
    else
      copy_file_force "$src" "$out"
    fi
  done < <(find "$COMMON_DIR" -type f -print0)
}

# Vendored packages: never rename. Mirror workspace/Libs → addon/Libs.
vendor_libs() {
  local dest="$1"
  local src rel dir base out_dir out stale

  if [[ -z "${LIBS_DIR:-}" || ! -d "$LIBS_DIR" ]]; then
    return 0
  fi

  # rsync --delete avoids rm -rf half-states on /mnt/*; ensure destination
  # exists first so mkstemp cannot fail if a prior sync wiped the tree.
  if command -v rsync >/dev/null 2>&1; then
    local rc=0
    mkdir -p -- "$dest/Libs"
    rsync -a --delete --exclude 'README.md' -- "$LIBS_DIR"/ "$dest/Libs"/ || rc=$?
    # 23/24 = partial / vanished — common on /mnt; treat as success.
    if [[ $rc -eq 0 || $rc -eq 23 || $rc -eq 24 ]]; then
      return 0
    fi
    echo "vendor_libs: rsync failed (exit $rc); falling back to copy" >&2
  fi

  # Fallback: move aside, copy fresh, then best-effort remove the stale tree.
  if [[ -e "$dest/Libs" ]]; then
    stale="$dest/Libs.__old_$$"
    mv -- "$dest/Libs" "$stale" 2>/dev/null || {
      rm -rf -- "$dest/Libs" 2>/dev/null || true
      stale=""
    }
  fi

  while IFS= read -r -d '' src; do
    rel="${src#"$LIBS_DIR"/}"
    rel="${rel//\\//}"

    # Docs only — do not ship into game AddOns.
    if [[ "$rel" == "README.md" ]]; then
      continue
    fi

    dir="$(dirname "$rel")"
    base="$(basename "$rel")"

    if [[ "$dir" == "." ]]; then
      out_dir="$dest/Libs"
    else
      out_dir="$dest/Libs/$dir"
    fi
    out="$out_dir/$base"

    mkdir -p -- "$out_dir"
    copy_file_force "$src" "$out"
  done < <(find "$LIBS_DIR" -type f -print0)

  if [[ -n "${stale:-}" ]]; then
    rm -rf -- "$stale" 2>/dev/null || true
  fi
}

vendor_shared() {
  local dest="$1"
  local mode="${2:-}"
  vendor_common "$dest" "$mode"
  vendor_libs "$dest"
}
