use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Manager};

const FLAVOR_DIR: &str = "_forever_";
const GAME_DIR: &str = "World of Warcraft";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AddonInfo {
    name: String,
    /// From `publicName` in `tkam.config`. The folder name when that line is blank.
    public_name: String,
    version: Option<String>,
    /// One sentence from `oneLiner` in `tkam.config`.
    one_liner: Option<String>,
    /// Prose after `---` in `tkam.config`, before the section headings.
    description: Option<String>,
    /// Bullets under `## Features` in `tkam.config`, in file order.
    features: Vec<String>,
    /// Bullets under `## Commands` in `tkam.config`, in file order.
    commands: Vec<String>,
    /// Release notes, newest first, as written in `tkam.config`.
    releases: Vec<ReleaseNote>,
    /// Absolute path to the icon named in `tkam.config`, when that file exists.
    icon_path: Option<String>,
    /// Absolute path to `screenshot.png` in the addon folder, when that file exists.
    screenshot_path: Option<String>,
    /// Unix seconds of the last source change. Set for bundled addons only.
    updated_at: Option<u64>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ReleaseNote {
    version: String,
    notes: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionResult {
    name: String,
    ok: bool,
    message: Option<String>,
}

#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct Config {
    addons_path: Option<String>,
}

#[tauri::command]
pub fn list_bundled_addons(app: AppHandle) -> Result<Vec<AddonInfo>, String> {
    let root = bundled_root(&app)?;
    let mut addons = read_addon_dirs(&root)?;
    let times = read_manifest(&root);
    for addon in &mut addons {
        addon.updated_at = times.get(&addon.name).copied();
    }
    Ok(addons)
}

/// `tkam-manifest.json` written by the build step: addon name -> last-changed Unix seconds.
fn read_manifest(root: &Path) -> HashMap<String, u64> {
    fs::read_to_string(root.join("tkam-manifest.json"))
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

/// Saved path first, then well-known install locations. `None` means the user must pick one.
#[tauri::command]
pub fn detect_addons_path(app: AppHandle) -> Result<Option<String>, String> {
    if let Some(saved) = load_config(&app).addons_path {
        if Path::new(&saved).is_dir() {
            return Ok(Some(saved));
        }
    }

    let found = candidate_game_roots()
        .into_iter()
        .map(|root| addons_dir_for_root(&root))
        .find(|dir| dir.is_dir())
        .map(|dir| dir.to_string_lossy().into_owned());

    if let Some(path) = &found {
        save_config(
            &app,
            &Config {
                addons_path: Some(path.clone()),
            },
        )?;
    }
    Ok(found)
}

/// Accepts the WoW root, the `_forever_` folder, or the AddOns folder itself.
#[tauri::command]
pub fn set_addons_path(app: AppHandle, path: String) -> Result<String, String> {
    let picked = PathBuf::from(&path);
    if !picked.is_dir() {
        return Err(format!("Folder not found: {path}"));
    }

    let resolved = [
        addons_dir_for_root(&picked),
        picked.join("Interface").join("AddOns"),
    ]
    .into_iter()
    .find(|dir| dir.is_dir())
    .unwrap_or(picked);

    let resolved = resolved.to_string_lossy().into_owned();
    save_config(
        &app,
        &Config {
            addons_path: Some(resolved.clone()),
        },
    )?;
    Ok(resolved)
}

#[tauri::command]
pub fn list_installed_addons(addons_path: String) -> Result<Vec<AddonInfo>, String> {
    let dir = PathBuf::from(&addons_path);
    if !dir.is_dir() {
        return Err(format!("AddOns folder not found: {addons_path}"));
    }
    read_addon_dirs(&dir)
}

#[tauri::command]
pub fn install_addons(
    app: AppHandle,
    addons_path: String,
    names: Vec<String>,
) -> Result<Vec<ActionResult>, String> {
    let source_root = bundled_root(&app)?;
    let target_root = PathBuf::from(&addons_path);
    if !target_root.is_dir() {
        return Err(format!("AddOns folder not found: {addons_path}"));
    }

    Ok(names
        .into_iter()
        .map(|name| {
            let outcome = install_one(&source_root, &target_root, &name);
            to_result(name, outcome)
        })
        .collect())
}

#[tauri::command]
pub fn uninstall_addons(addons_path: String, names: Vec<String>) -> Result<Vec<ActionResult>, String> {
    let target_root = PathBuf::from(&addons_path);
    if !target_root.is_dir() {
        return Err(format!("AddOns folder not found: {addons_path}"));
    }

    Ok(names
        .into_iter()
        .map(|name| {
            let outcome = uninstall_one(&target_root, &name);
            to_result(name, outcome)
        })
        .collect())
}

fn install_one(source_root: &Path, target_root: &Path, name: &str) -> Result<(), String> {
    validate_name(name)?;
    let src = source_root.join(name);
    if !src.is_dir() {
        return Err("Not bundled with this version of TKAM".into());
    }

    let dest = target_root.join(name);
    if dest.exists() {
        // The game can hold files open on Windows; if the folder cannot be
        // removed, copy over it so at least every bundled file is current.
        let _ = fs::remove_dir_all(&dest);
    }
    copy_dir_recursive(&src, &dest).map_err(|e| e.to_string())
}

fn uninstall_one(target_root: &Path, name: &str) -> Result<(), String> {
    validate_name(name)?;
    let dest = target_root.join(name);
    if !dest.exists() {
        return Ok(());
    }
    fs::remove_dir_all(&dest).map_err(|e| e.to_string())
}

fn to_result(name: String, outcome: Result<(), String>) -> ActionResult {
    match outcome {
        Ok(()) => ActionResult {
            name,
            ok: true,
            message: None,
        },
        Err(message) => ActionResult {
            name,
            ok: false,
            message: Some(message),
        },
    }
}

fn validate_name(name: &str) -> Result<(), String> {
    let bad = name.is_empty()
        || name.starts_with('.')
        || name.contains('/')
        || name.contains('\\')
        || name.contains(':');
    if bad {
        Err(format!("Invalid addon name: {name}"))
    } else {
        Ok(())
    }
}

fn copy_dir_recursive(src: &Path, dest: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dest)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dest.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir_recursive(&from, &to)?;
        } else {
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

fn bundled_root(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .resolve("addons", BaseDirectory::Resource)
        .map_err(|e| e.to_string())
}

fn read_addon_dirs(root: &Path) -> Result<Vec<AddonInfo>, String> {
    let entries = fs::read_dir(root).map_err(|e| format!("{}: {e}", root.display()))?;

    let mut addons: Vec<AddonInfo> = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                return None;
            }
            let version = read_version(&entry.path(), &name);
            let config = read_tkam_config(&entry.path());
            let public_name = config
                .public_name
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| name.clone());
            let icon_path = config
                .icon
                .as_deref()
                .and_then(|icon| resolve_icon(&entry.path(), icon));
            let screenshot_path = resolve_icon(&entry.path(), "screenshot.png");
            Some(AddonInfo {
                name,
                public_name,
                version,
                one_liner: config.one_liner,
                description: config.description,
                features: config.features,
                commands: config.commands,
                releases: config.releases,
                icon_path,
                screenshot_path,
                updated_at: None,
            })
        })
        .collect();

    addons.sort_by_key(|a| a.name.to_lowercase());
    Ok(addons)
}

/// `## Version` from `<name>.toc`, or the first `.toc` in the folder.
/// Public name, one-liner, icon, description, features, and commands come from `tkam.config`.
fn read_version(dir: &Path, name: &str) -> Option<String> {
    let preferred = dir.join(format!("{name}.toc"));
    let toc = if preferred.is_file() {
        Some(preferred)
    } else {
        fs::read_dir(dir).ok().and_then(|entries| {
            entries.filter_map(Result::ok).map(|e| e.path()).find(|p| {
                p.extension()
                    .map(|ext| ext.eq_ignore_ascii_case("toc"))
                    .unwrap_or(false)
            })
        })
    };

    let contents = toc.and_then(|p| fs::read_to_string(p).ok())?;
    for line in contents.lines() {
        let line = line.trim_start_matches('\u{feff}').trim();
        let Some((key, value)) = line
            .strip_prefix("##")
            .and_then(|rest| rest.split_once(':'))
        else {
            continue;
        };
        if key.trim() == "Version" {
            let value = value.trim();
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

/// Parsed `tkam.config`. Missing keys stay empty.
#[derive(Default)]
struct TkamConfig {
    public_name: Option<String>,
    one_liner: Option<String>,
    icon: Option<String>,
    description: Option<String>,
    features: Vec<String>,
    commands: Vec<String>,
    releases: Vec<ReleaseNote>,
}

fn read_tkam_config(dir: &Path) -> TkamConfig {
    fs::read_to_string(dir.join("tkam.config"))
        .map(|text| parse_tkam_config(&text))
        .unwrap_or_default()
}

/// Header lines are `key: value` until a line that is only `---`.
/// The body is the description, then `## Features` and `## Commands`.
/// Any other `## ` heading starts a release, and its `- ` lines are that version's notes.
fn parse_tkam_config(text: &str) -> TkamConfig {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut public_name = None;
    let mut one_liner = None;
    let mut icon = None;
    let mut in_body = false;
    let mut body: Vec<&str> = Vec::new();

    for line in text.lines() {
        if !in_body {
            if line.trim() == "---" {
                in_body = true;
                continue;
            }
            let Some((key, value)) = line.split_once(':') else {
                continue;
            };
            let value = value.trim();
            if value.is_empty() {
                continue;
            }
            match key.trim() {
                "publicName" if public_name.is_none() => public_name = Some(value.to_string()),
                "oneLiner" if one_liner.is_none() => one_liner = Some(value.to_string()),
                "icon" if icon.is_none() => icon = Some(value.to_string()),
                _ => {}
            }
        } else {
            body.push(line);
        }
    }

    let (description, features, commands, releases) = parse_about_body(&body.join("\n"));

    TkamConfig {
        public_name,
        one_liner,
        icon,
        description,
        features,
        commands,
        releases,
    }
}

#[derive(Clone, Copy, PartialEq)]
enum AboutSection {
    Description,
    Features,
    Commands,
    Release,
}

/// Description prose comes first. `## Features` and `## Commands` name those
/// lists, and only `- ` lines under that heading belong to it. Any other
/// `## ` heading starts a release.
fn parse_about_body(body: &str) -> (Option<String>, Vec<String>, Vec<String>, Vec<ReleaseNote>) {
    let mut paragraphs: Vec<String> = Vec::new();
    let mut line_buf: Vec<&str> = Vec::new();
    let mut features = Vec::new();
    let mut commands = Vec::new();
    let mut releases: Vec<ReleaseNote> = Vec::new();
    let mut section = AboutSection::Description;

    for line in body.lines() {
        let trimmed = line.trim();
        if let Some(heading) = trimmed.strip_prefix("## ") {
            if section == AboutSection::Description && !line_buf.is_empty() {
                paragraphs.push(line_buf.join(" "));
                line_buf.clear();
            }
            let heading = heading.trim();
            if heading.is_empty() {
                continue;
            }
            if heading.eq_ignore_ascii_case("features") {
                section = AboutSection::Features;
            } else if heading.eq_ignore_ascii_case("commands") {
                section = AboutSection::Commands;
            } else {
                releases.push(ReleaseNote {
                    version: heading.to_string(),
                    notes: Vec::new(),
                });
                section = AboutSection::Release;
            }
            continue;
        }
        if let Some(item) = trimmed.strip_prefix("- ") {
            let item = item.trim();
            if item.is_empty() {
                continue;
            }
            match section {
                AboutSection::Features => features.push(item.to_string()),
                AboutSection::Commands => commands.push(item.to_string()),
                AboutSection::Release => {
                    if let Some(release) = releases.last_mut() {
                        release.notes.push(item.to_string());
                    }
                }
                AboutSection::Description => {
                    if !line_buf.is_empty() {
                        paragraphs.push(line_buf.join(" "));
                        line_buf.clear();
                    }
                    paragraphs.push(item.to_string());
                }
            }
            continue;
        }
        if trimmed.is_empty() {
            if section == AboutSection::Description && !line_buf.is_empty() {
                paragraphs.push(line_buf.join(" "));
                line_buf.clear();
            }
            continue;
        }
        if section == AboutSection::Description {
            line_buf.push(trimmed);
        }
    }

    if section == AboutSection::Description && !line_buf.is_empty() {
        paragraphs.push(line_buf.join(" "));
    }

    let description = {
        let text = paragraphs.join("\n\n");
        if text.is_empty() { None } else { Some(text) }
    };
    (description, features, commands, releases)
}

/// `icon` in the config is relative to the addon folder. Paths that leave that folder are ignored.
fn resolve_icon(dir: &Path, icon: &str) -> Option<String> {
    let rel = Path::new(icon.trim());
    let escapes = rel.is_absolute()
        || rel
            .components()
            .any(|c| matches!(c, std::path::Component::ParentDir));
    if escapes {
        return None;
    }
    let path = dir.join(rel);
    path.is_file().then(|| path.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::parse_tkam_config;

    #[test]
    fn parses_header_and_markdown_body() {
        let text = "\
publicName: JunkMaster
oneLiner: Sells junk.
icon: icon.png

---

Sells gray items.

## Features

- One
- Two

## Commands

- `/jm` opens the ledger.
";
        let cfg = parse_tkam_config(text);
        assert_eq!(cfg.public_name.as_deref(), Some("JunkMaster"));
        assert_eq!(cfg.one_liner.as_deref(), Some("Sells junk."));
        assert_eq!(cfg.icon.as_deref(), Some("icon.png"));
        assert_eq!(cfg.description.as_deref(), Some("Sells gray items."));
        assert_eq!(cfg.features, vec!["One".to_string(), "Two".to_string()]);
        assert_eq!(cfg.commands, vec!["`/jm` opens the ledger.".to_string()]);
        assert!(cfg.releases.is_empty());
    }

    #[test]
    fn parses_release_notes_after_features() {
        let text = "\
publicName: JunkMaster
oneLiner: Sells junk.

---

Sells gray items.

## Features

- Keeps a ledger

## Commands

- `/jm` opens the ledger.

## 0.3.3
- Sells gray items at a vendor

## 0.3.2
- First ledger
";
        let cfg = parse_tkam_config(text);
        assert_eq!(cfg.features, vec!["Keeps a ledger".to_string()]);
        assert_eq!(cfg.commands, vec!["`/jm` opens the ledger.".to_string()]);
        assert_eq!(cfg.releases.len(), 2);
        assert_eq!(cfg.releases[0].version, "0.3.3");
        assert_eq!(
            cfg.releases[0].notes,
            vec!["Sells gray items at a vendor".to_string()]
        );
        assert_eq!(cfg.releases[1].version, "0.3.2");
        assert_eq!(cfg.releases[1].notes, vec!["First ledger".to_string()]);
    }

    #[test]
    fn missing_separator_has_no_description() {
        let cfg = parse_tkam_config("publicName: Wen Ding?\n");
        assert_eq!(cfg.public_name.as_deref(), Some("Wen Ding?"));
        let blank = parse_tkam_config("publicName:\n");
        assert!(blank.public_name.is_none());
        assert!(cfg.description.is_none());
        assert!(cfg.features.is_empty());
        assert!(cfg.commands.is_empty());
    }

    #[test]
    fn bullets_outside_a_heading_are_not_features() {
        let text = "\
publicName: JunkMaster
oneLiner: Sells junk.

---

Sells gray items.

- Not a feature

## Features

- A feature
";
        let cfg = parse_tkam_config(text);
        assert_eq!(
            cfg.description.as_deref(),
            Some("Sells gray items.\n\nNot a feature")
        );
        assert_eq!(cfg.features, vec!["A feature".to_string()]);
        assert!(cfg.commands.is_empty());
        assert!(cfg.releases.is_empty());
    }
}

fn addons_dir_for_root(root: &Path) -> PathBuf {
    root.join(FLAVOR_DIR).join("Interface").join("AddOns")
}

#[cfg(target_os = "windows")]
fn candidate_game_roots() -> Vec<PathBuf> {
    let mut roots = battle_net_install_paths();
    for drive in b'C'..=b'H' {
        let drive = PathBuf::from(format!("{}:\\", drive as char));
        for rel in [
            "Program Files (x86)",
            "Program Files",
            "Battle.net",
            "Games",
            "",
        ] {
            roots.push(drive.join(rel).join(GAME_DIR));
        }
    }
    roots
}

/// The Battle.net agent stores install paths as plain strings inside its
/// protobuf `product.db`; scan for `X:/.../World of Warcraft`.
#[cfg(target_os = "windows")]
fn battle_net_install_paths() -> Vec<PathBuf> {
    let program_data = std::env::var_os("ProgramData")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("C:\\ProgramData"));
    let Ok(bytes) = fs::read(program_data.join("Battle.net").join("Agent").join("product.db")) else {
        return Vec::new();
    };

    let text = String::from_utf8_lossy(&bytes);
    let mut paths = Vec::new();
    let mut search_from = 0;
    while let Some(offset) = text[search_from..].find(GAME_DIR) {
        let end = search_from + offset + GAME_DIR.len();
        let head = &text[..search_from + offset];
        if let Some(colon) = head.rfind(":/").or_else(|| head.rfind(":\\")) {
            if colon >= 1 && head.is_char_boundary(colon - 1) {
                let candidate = &text[colon - 1..end];
                let starts_with_drive = candidate
                    .chars()
                    .next()
                    .map(|c| c.is_ascii_alphabetic())
                    .unwrap_or(false);
                if starts_with_drive && !candidate.chars().any(char::is_control) {
                    paths.push(PathBuf::from(candidate));
                }
            }
        }
        search_from = end;
    }
    paths
}

#[cfg(target_os = "macos")]
fn candidate_game_roots() -> Vec<PathBuf> {
    let mut roots = vec![PathBuf::from("/Applications").join(GAME_DIR)];
    if let Some(home) = std::env::var_os("HOME") {
        roots.push(PathBuf::from(home).join("Applications").join(GAME_DIR));
    }
    roots
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn candidate_game_roots() -> Vec<PathBuf> {
    Vec::new()
}

fn config_file(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_config_dir()
        .map(|dir| dir.join("config.json"))
        .map_err(|e| e.to_string())
}

fn load_config(app: &AppHandle) -> Config {
    config_file(app)
        .ok()
        .and_then(|path| fs::read_to_string(path).ok())
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

fn save_config(app: &AppHandle, config: &Config) -> Result<(), String> {
    let path = config_file(app)?;
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(config).map_err(|e| e.to_string())?;
    fs::write(path, text).map_err(|e| e.to_string())
}
