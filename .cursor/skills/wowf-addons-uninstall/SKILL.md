---
name: wowf-addons-uninstall
description: >-
  Uninstalls addons from the WoW Forever game AddOns folder using
  Scripts/wowf-addons-uninstall.sh. Use when the user asks to uninstall,
  remove, clear, wipe, empty, or reset WoW Forever addons, or mentions
  wowf-addons-uninstall.
---

# WoW Forever AddOns Uninstall

## When to use

Run this when the user wants addons removed from the game AddOns folder.

## Script

`Scripts/wowf-addons-uninstall.sh`

Default target: `/mnt/d/Battle.net/World of Warcraft/_forever_/Interface/AddOns`

## How to run

Must run under **bash** (WSL). Do not use PowerShell `.\script.sh`.

From PowerShell or any Windows shell:

```bash
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-uninstall.sh" --force JunkMaster
bash "/mnt/c/Users/tambykojak/Create/WoW Forever Addons/Scripts/wowf-addons-uninstall.sh" --force --all
```

### Arguments

| Arg | Meaning |
|-----|---------|
| `addon-name` | Remove only that folder under the game AddOns path. Mutually exclusive with `--all`. |
| `--all` | Remove every item under the game AddOns path. Mutually exclusive with an addon name. |

One of `addon-name` or `--all` is **required**.

### Flags

| Flag | Meaning |
|------|---------|
| `-f` / `--force` | Skip confirmation (required for non-interactive agent runs) |
| `-n` / `--what-if` | Preview only; delete nothing |
| `--path PATH` | Override AddOns destination |

## Agent rules

1. Prefer `--what-if` first if the user only wants to see what would be removed.
2. For a real uninstall from the agent, use `--force` so the prompt does not hang.
3. Require `--all` or a specific addon name — ask if the user did not specify.
4. After running, briefly report what was removed (or that the folder was already empty / addon missing).
5. This does **not** touch the workspace `Addons/`, `Common/`, or `Outputs/` folders.
