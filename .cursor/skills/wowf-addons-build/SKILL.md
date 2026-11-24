---
name: wowf-addons-build
description: >-
  Builds workspace addons into Outputs/ using Scripts/wowf-addons-build.sh.
  Copies Common/ beside src/ and Libs/ unchanged into each built addon;
  forces WoWF.DevMode = false for production. Use when
  the user asks to build, package, or export WoW Forever addons into
  Outputs, or mentions wowf-addons-build.
---

# WoW Forever AddOns Build

## When to use

Run this when the user wants ready-to-copy addon folders under `Outputs/`.

## Layout

| Path | Role |
|------|------|
| `Addons/` | Source addon folders (e.g. `JunkMaster`) |
| `Common/` | First-party shared code — copied whole to `Common/` beside `src/`. No renames |
| `Libs/` | Third-party packages — mirrored to `Libs/**`, never renamed |
| `Outputs/` | Build destination (not installed into the game) |
| `Scripts/` | build/install/uninstall/dev scripts |

## Script

`Scripts/wowf-addons-build.sh`

## How to run

Must run under **bash** (WSL). Do not use PowerShell `.\script.sh`.

From PowerShell or any Windows shell:

```bash
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-build.sh" --all
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-build.sh" JunkMaster
```

### Arguments

| Arg | Meaning |
|-----|---------|
| `addon-name` | Build only that folder under `Addons/`. Mutually exclusive with `--all`. |
| `--all` | Wipe `Outputs/` then build every addon. Mutually exclusive with an addon name. |

One of `addon-name` or `--all` is **required**.

### Flags

| Flag | Meaning |
|------|---------|
| `-n` / `--what-if` | Preview only; write nothing |
| `--out PATH` | Override Outputs destination |

Building one addon overwrites only `Outputs/<name>/`. Building `--all` wipes `Outputs/` first so stale folders disappear.

## Agent rules

1. Prefer `--what-if` first if the user only wants a preview.
2. Require `--all` or a specific addon name — ask if the user did not specify.
3. Only folders under workspace `Addons/` are built. `Common/` and `Libs/` are never top-level Outputs; each is copied into the addon with its original names.
4. Production builds force `WoWF.DevMode = false` in `Common/DevMode.lua`. Install/dev keep `DevMode = true` from workspace Common.
5. After running, briefly report how many addons were built and the Outputs path.
