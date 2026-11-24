---
name: wowf-addons-install
description: >-
  Installs workspace addons into the WoW Forever game AddOns folder using
  Scripts/wowf-addons-install.sh. Copies Addons/<name>, then copies
  Common/ beside src/ and Libs/ unchanged into each addon root. Use
  when the user asks to install, deploy, sync, or update WoW Forever
  addons, or mentions wowf-addons-install.
---

# WoW Forever AddOns Install

## When to use

Run this when the user wants workspace addons copied into the game.

## Layout

| Path | Role |
|------|------|
| `Addons/` | Installable addon folders (e.g. `JunkMaster`) |
| `Common/` | First-party shared code — copied whole to `Common/` beside `src/`. No renames |
| `Libs/` | Third-party packages — mirrored to `Libs/**`, never renamed |
| `Scripts/` | build/install/uninstall/dev scripts |

Destination: `/mnt/d/Battle.net/World of Warcraft/_forever_/Interface/AddOns`

## Script

`Scripts/wowf-addons-install.sh`

## How to run

Must run under **bash** (WSL). Do not use PowerShell `.\script.sh`.

From PowerShell or any Windows shell:

```bash
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-install.sh" --update --all
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-install.sh" --update JunkMaster
```

### Arguments

| Arg | Meaning |
|-----|---------|
| `addon-name` | Install only that folder under `Addons/`. Mutually exclusive with `--all`. |
| `--all` | Install every addon under `Addons/`. Mutually exclusive with an addon name. |

One of `addon-name` or `--all` is **required**.

### Flags

| Flag | Meaning |
|------|---------|
| `-u` / `--update` | Overwrite existing addons without prompting (use for non-interactive agent runs) |
| `-n` / `--what-if` | Preview only; copy nothing |
| `--path PATH` | Override AddOns destination |

Default (no `--update`): new addons are copied; existing ones prompt per addon.

## Agent rules

1. Prefer `--what-if` first if the user only wants a preview.
2. For a real install from the agent, use `--update` so existing-addon prompts do not hang.
3. Require `--all` or a specific addon name — ask if the user did not specify.
4. Only folders under workspace `Addons/` are installed as AddOns. `Common/` and `Libs/` are never top-level AddOns; each is copied into the addon with its original names. Install keeps `WoWF.DevMode = true` (production `build` forces false in `Common/DevMode.lua`).
5. After running, briefly report installed / updated / skipped counts.
