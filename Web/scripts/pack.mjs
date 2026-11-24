// Copies addon icons and screenshots into the site.

import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const workspace = resolve(siteRoot, "..");
const addonsDir = resolve(workspace, "Addons");
const iconsDir = resolve(siteRoot, "public", "icons");
const shotsDir = resolve(siteRoot, "public", "screenshots");

mkdirSync(iconsDir, { recursive: true });
mkdirSync(shotsDir, { recursive: true });

const names = readdirSync(addonsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
  .map((entry) => entry.name);

for (const name of names) {
  const icon = resolve(addonsDir, name, "icon.png");
  if (existsSync(icon)) cpSync(icon, resolve(iconsDir, `${name}.png`));

  const shot = resolve(addonsDir, name, "screenshot.png");
  if (existsSync(shot)) cpSync(shot, resolve(shotsDir, `${name}.png`));
}
