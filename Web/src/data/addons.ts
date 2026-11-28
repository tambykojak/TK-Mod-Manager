import { existsSync, readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export type Release = {
  version: string;
  title: string;
  date: string;
  notes: string[];
};

export type Addon = {
  name: string;
  slug: string;
  publicName: string;
  version: string;
  oneLiner: string;
  description: string;
  features: string[];
  commands: string[];
  releases: Release[];
  icon: string | null;
  screenshot: string | null;
};

const workspace = resolve(fileURLToPath(new URL(".", import.meta.url)), "..", "..", "..");
const addonsDir = resolve(workspace, "Addons");
const sitePublic = resolve(workspace, "Web", "public");

function versionOf(tocPath: string): string {
  if (!existsSync(tocPath)) return "";
  for (const line of readFileSync(tocPath, "utf8").split(/\r?\n/)) {
    const match = line.match(/^##\s*Version:\s*(.+)$/i);
    if (match) return match[1].trim();
  }
  return "";
}

function parseConfig(text: string): {
  publicName: string;
  oneLiner: string;
  description: string;
  features: string[];
  commands: string[];
} {
  const clean = text.replace(/^\uFEFF/, "");
  const [header, body = ""] = clean.split(/\r?\n---\r?\n/);
  let publicName = "";
  let oneLiner = "";
  for (const line of header.split(/\r?\n/)) {
    const split = line.indexOf(":");
    if (split === -1) continue;
    const key = line.slice(0, split).trim();
    const value = line.slice(split + 1).trim();
    if (key === "publicName" && !publicName) publicName = value;
    if (key === "oneLiner" && !oneLiner) oneLiner = value;
  }

  type Section = "description" | "features" | "commands" | "release";
  let section: Section = "description";
  const paragraphs: string[] = [];
  let paragraph: string[] = [];
  const features: string[] = [];
  const commands: string[] = [];

  const flush = () => {
    const text = paragraph.join(" ").trim();
    if (text) paragraphs.push(text);
    paragraph = [];
  };

  for (const raw of body.split(/\r?\n/)) {
    const line = raw.trim();
    const heading = line.match(/^##\s+(.+)$/);
    if (heading) {
      if (section === "description") flush();
      const name = heading[1].trim().toLowerCase();
      if (name === "features") section = "features";
      else if (name === "commands") section = "commands";
      else section = "release";
      continue;
    }
    if (line.startsWith("- ")) {
      const item = line.slice(2).trim();
      if (!item) continue;
      if (section === "features") features.push(item);
      else if (section === "commands") commands.push(item);
      else if (section === "description") {
        flush();
        paragraphs.push(item);
      }
      continue;
    }
    if (!line) {
      if (section === "description") flush();
      continue;
    }
    if (section === "description") paragraph.push(line);
  }
  if (section === "description") flush();

  return { publicName, oneLiner, description: paragraphs.join("\n\n"), features, commands };
}

function parseReleases(text: string): Release[] {
  const releases: Release[] = [];
  let current: Release | null = null;

  for (const raw of text.replace(/^\uFEFF/, "").split(/\r?\n/)) {
    const line = raw.trim();
    const heading = line.match(/^##\s+(.+)$/);
    if (heading) {
      if (current) releases.push(current);
      const [version, title = ""] = heading[1].split(/\s+—\s+/);
      current = { version: version.trim(), title: title.trim(), date: "", notes: [] };
      continue;
    }
    if (!current || line === "---" || !line) continue;
    if (line.startsWith("- ")) current.notes.push(line.slice(2).trim());
    else if (!current.date) current.date = line;
  }
  if (current) releases.push(current);
  return releases;
}

export function loadAddons(): Addon[] {
  if (!existsSync(addonsDir)) return [];

  const addons = readdirSync(addonsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => {
      const name = entry.name;
      const dir = resolve(addonsDir, name);
      const configPath = resolve(dir, "tkam.config");
      const releasePath = resolve(dir, "RELEASE.md");
      const config = existsSync(configPath)
        ? parseConfig(readFileSync(configPath, "utf8"))
        : { publicName: "", oneLiner: "", description: "", features: [], commands: [] };
      const version = versionOf(resolve(dir, `${name}.toc`));
      const iconFile = resolve(sitePublic, "icons", `${name}.png`);
      const shotFile = resolve(sitePublic, "screenshots", `${name}.png`);

      const addon: Addon = {
        name,
        slug: name.toLowerCase(),
        publicName: config.publicName || name,
        version,
        oneLiner: config.oneLiner,
        description: config.description,
        features: config.features,
        commands: config.commands,
        releases: existsSync(releasePath) ? parseReleases(readFileSync(releasePath, "utf8")) : [],
        icon: existsSync(iconFile) ? `/icons/${name}.png` : null,
        screenshot: existsSync(shotFile) ? `/screenshots/${name}.png` : null,
      };
      return addon;
    });

  addons.sort((a, b) => a.publicName.localeCompare(b.publicName, undefined, { sensitivity: "base" }));
  return addons;
}

export function findAddon(slug: string): Addon | undefined {
  return loadAddons().find((addon) => addon.slug === slug);
}
