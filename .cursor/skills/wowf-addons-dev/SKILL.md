---
name: wowf-addons-dev
description: >-
  Starts a watch/dev process for a WoW Forever addon using
  Scripts/wowf-addons-dev.sh. Polls Addons/<name>, Common, and Libs,
  then auto-runs build + install --update on change. Use when the user
  asks to start addon dev mode, watch an addon, auto-build/install on
  save, or mentions wowf-addons-dev.
---

# WoW Forever AddOns Dev Watch

## When to use

Run this when the user wants continuous build + install while editing one addon.

## Script

`Scripts/wowf-addons-dev.sh`

With no names, watches every folder under `Addons/`. With names, watches only those addons. Always watches workspace `Common/` and `Libs/`. A new addon folder is picked up without restarting.

On change, for each affected addon it runs:

1. `wowf-addons-build.sh <addon-name>` → `Outputs/<addon-name>/`
2. `wowf-addons-install.sh --update <addon-name>` → game AddOns folder

Only addons whose folder changed are rebuilt. A change in `Common/` or `Libs/` rebuilds every watched addon.

Uses **polling** (default 1s) so Windows/Cursor edits on `/mnt/c` are detected.

## How to run

Must run under **bash** (WSL). Do not use PowerShell `.\script.sh`.

This is a long-running process — start it in the background or a dedicated terminal, and stop with Ctrl+C.

```bash
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-dev.sh"
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-dev.sh" JunkMaster
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-dev.sh" JunkMaster WenDing --interval 0.5
```

### Arguments

| Arg | Meaning |
|-----|---------|
| `addon-name ...` | Optional. One or more folders under workspace `Addons/` to watch. Omit to watch all |

### Flags

| Flag | Meaning |
|------|---------|
| `--interval SECONDS` | Poll interval (default: `1`) |
| `--skip-initial` | Skip the build/install that runs at startup |
| `--path PATH` | Override AddOns destination |

## Agent rules

1. Names are optional. With none given, watch all addons; pass names only when the user asks for specific ones.
2. Start the watcher as a **background** shell with `block_until_ms: 0` (or equivalent) so the session stays usable.
3. Do not also run a one-shot build/install unless asked; the watcher builds and installs on start by default.
4. When stopping, kill the background process if the user asks to stop watching.
5. After starting, report which addons are watched, the watch path, and that Ctrl+C / killing the process stops it.
6. **On addon rename:** stop the old-name watch (and any stale install of the old folder), then start a new watch for the **new** name in the same turn — do not wait to be asked.
