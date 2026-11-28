import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";

/**
 * Looks for a newer TKAM release. Returns null when there is none, or when the
 * update feed can't be reached. A failed check should never block the app.
 */
export async function findUpdate(): Promise<Update | null> {
  try {
    return await check();
  } catch {
    return null;
  }
}

/** Downloads and installs the update, then restarts TKAM. */
export async function installUpdate(update: Update): Promise<void> {
  await update.downloadAndInstall();
  await relaunch();
}
