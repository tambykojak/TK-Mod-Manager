// Builds every workspace addon into Outputs/ (production, DevMode off) so
// tauri.conf.json can bundle that folder as the app's "addons" resource.
// Also writes Outputs/tkmm-manifest.json with each addon's last-changed time
// (newest file mtime under Addons/<name>, in Unix seconds).
//
// Env:
//   TKMM_BASH=<path>         bash 4+ to run the build script (default: bash)
//   TKMM_SKIP_ADDON_BUILD=1  reuse the existing Outputs/ as-is

import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const workspaceRoot = resolve(here, "..", "..");
const outputsDir = resolve(workspaceRoot, "Outputs");
const addonsSourceDir = resolve(workspaceRoot, "Addons");

if (process.env.TKMM_SKIP_ADDON_BUILD !== "1") {
  const bash = process.env.TKMM_BASH || "bash";
  const result = spawnSync(bash, ["Scripts/wowf-addons-build.sh", "--all"], {
    cwd: workspaceRoot,
    stdio: "inherit",
  });

  if (result.error) {
    console.error(
      `Could not run "${bash}": ${result.error.message}\n` +
        "Install Git Bash or WSL (Windows) or bash 4+ (macOS: brew install bash), " +
        "or point TKMM_BASH at one.",
    );
    process.exit(1);
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

const addons = existsSync(outputsDir)
  ? readdirSync(outputsDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
      .map((entry) => entry.name)
  : [];

if (addons.length === 0) {
  console.error(`No built addons found in ${outputsDir}`);
  process.exit(1);
}

// Newest modification time (seconds) of any file under dir, recursively.
function newestMtime(dir) {
  let newest = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    const time = entry.isDirectory()
      ? newestMtime(path)
      : Math.floor(statSync(path).mtimeMs / 1000);
    if (time > newest) newest = time;
  }
  return newest;
}

const manifest = {};
for (const name of addons) {
  const source = join(addonsSourceDir, name);
  if (existsSync(source)) {
    manifest[name] = newestMtime(source);
  }
}
writeFileSync(join(outputsDir, "tkmm-manifest.json"), JSON.stringify(manifest, null, 2));

console.log(`Bundling ${addons.length} addons: ${addons.join(", ")}`);
