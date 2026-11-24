import { invoke } from "@tauri-apps/api/core";

export type ReleaseNote = {
  version: string;
  notes: string[];
};

export type AddonInfo = {
  name: string;
  publicName: string;
  version: string | null;
  oneLiner: string | null;
  description: string | null;
  features: string[];
  commands: string[];
  releases: ReleaseNote[];
  iconPath: string | null;
  screenshotPath: string | null;
  /** Unix seconds of the last source change (bundled addons only). */
  updatedAt: number | null;
};

export type ActionResult = {
  name: string;
  ok: boolean;
  message: string | null;
};

export const listBundledAddons = () => invoke<AddonInfo[]>("list_bundled_addons");

export const detectAddonsPath = () => invoke<string | null>("detect_addons_path");

export const setAddonsPath = (path: string) => invoke<string>("set_addons_path", { path });

export const listInstalledAddons = (addonsPath: string) =>
  invoke<AddonInfo[]>("list_installed_addons", { addonsPath });

export const installAddons = (addonsPath: string, names: string[]) =>
  invoke<ActionResult[]>("install_addons", { addonsPath, names });

export const uninstallAddons = (addonsPath: string, names: string[]) =>
  invoke<ActionResult[]>("uninstall_addons", { addonsPath, names });
