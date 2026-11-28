import { useCallback, useEffect, useMemo, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import {
  type ActionResult,
  type AddonInfo,
  detectAddonsPath,
  installAddons,
  listBundledAddons,
  listInstalledAddons,
  setAddonsPath,
  uninstallAddons,
} from "./api";
import { AddonPage } from "./AddonDetail";
import { findUpdate, installUpdate } from "./updater";
import type { Update } from "@tauri-apps/plugin-updater";
import { type Theme, applyTheme, loadTheme, saveTheme } from "./theme";

type Status = "not-installed" | "update" | "current";
type SortKey = "name" | "updated" | "action";
type FilterId = "installed" | "update" | "all";

const FILTERS: { id: FilterId; label: string }[] = [
  { id: "all", label: "All" },
  { id: "installed", label: "Installed" },
  { id: "update", label: "Needs Update" },
];
const STATUS_LABEL: Record<Status, string> = {
  "not-installed": "Not installed",
  update: "Update available",
  current: "Up to date",
};
/** Action order: Update, then Installed (up to date), then Install. */
const ACTION_RANK: Record<Status, number> = { update: 0, current: 1, "not-installed": 2 };

const THEMES: { id: Theme; label: string }[] = [
  { id: "dark", label: "Dark" },
  { id: "light", label: "Light" },
];

type Notice = { kind: "ok" | "error"; text: string };

function errorText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

function summarize(verb: string, results: ActionResult[]): Notice {
  const failed = results.filter((r) => !r.ok);
  const okCount = results.length - failed.length;
  if (failed.length === 0) {
    return { kind: "ok", text: `${verb} ${okCount} addon${okCount === 1 ? "" : "s"}.` };
  }
  const details = failed.map((r) => `${r.name}: ${r.message ?? "failed"}`).join("; ");
  return { kind: "error", text: `${verb} ${okCount}, failed ${failed.length}. ${details}` };
}

function displayName(addon: AddonInfo): string {
  return addon.publicName;
}

const ONE_LINER_LIMIT = 50;

/** Caps the one-liner at 50 characters, ending in "..." when cut. */
function clipOneLiner(text: string | null): string {
  if (!text) return "";
  if (text.length <= ONE_LINER_LIMIT) return text;
  return `${text.slice(0, ONE_LINER_LIMIT - 3).trimEnd()}...`;
}

function formatUpdated(seconds: number | null): string {
  if (seconds === null) return "-";
  return new Date(seconds * 1000).toLocaleString(undefined, {
    year: "2-digit",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

export default function App() {
  const [bundled, setBundled] = useState<AddonInfo[]>([]);
  const [installed, setInstalled] = useState<Map<string, AddonInfo>>(new Map());
  const [addonsPath, setPath] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("name");
  const [sortReversed, setSortReversed] = useState(false);
  const [filter, setFilter] = useState<FilterId>("all");
  const [busyName, setBusyName] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [openName, setOpenName] = useState<string | null>(null);
  const [appUpdate, setAppUpdate] = useState<Update | null>(null);
  const [updatingApp, setUpdatingApp] = useState(false);

  const [theme, setTheme] = useState<Theme>(loadTheme);

  const busy = busyName !== null;

  const pickTheme = (next: Theme) => {
    setTheme(next);
    applyTheme(next);
    saveTheme(next);
  };

  useEffect(() => {
    findUpdate().then(setAppUpdate);
  }, []);

  const updateApp = async () => {
    if (!appUpdate) return;
    setUpdatingApp(true);
    try {
      await installUpdate(appUpdate);
    } catch (err) {
      setNotice({ kind: "error", text: errorText(err) });
      setUpdatingApp(false);
    }
  };

  const refreshInstalled = useCallback(async (path: string | null) => {
    if (!path) {
      setInstalled(new Map());
      return;
    }
    try {
      const list = await listInstalledAddons(path);
      setInstalled(new Map(list.map((a) => [a.name, a])));
    } catch (err) {
      setInstalled(new Map());
      setNotice({ kind: "error", text: errorText(err) });
    }
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const [addons, path] = await Promise.all([listBundledAddons(), detectAddonsPath()]);
        setBundled(addons);
        setPath(path);
        await refreshInstalled(path);
      } catch (err) {
        setNotice({ kind: "error", text: errorText(err) });
      }
    })();
  }, [refreshInstalled]);

  const statusOf = useCallback(
    (addon: AddonInfo): Status => {
      const current = installed.get(addon.name);
      if (!current) return "not-installed";
      return current.version === addon.version ? "current" : "update";
    },
    [installed],
  );

  const sorted = useMemo(() => {
    const list = [...bundled];
    list.sort((a, b) => {
      if (sortKey === "action") {
        const diff = ACTION_RANK[statusOf(a)] - ACTION_RANK[statusOf(b)];
        if (diff !== 0) return sortReversed ? -diff : diff;
      }
      if (sortKey === "updated") {
        const diff = (b.updatedAt ?? -1) - (a.updatedAt ?? -1);
        if (diff !== 0) return sortReversed ? -diff : diff;
      }
      return displayName(a).localeCompare(displayName(b), undefined, { sensitivity: "base" });
    });
    return list;
  }, [bundled, sortKey, sortReversed, statusOf]);

  /** Clicking the active sort header flips its direction. */
  const pickSort = (key: SortKey) => {
    if (key === sortKey) {
      setSortReversed((value) => !value);
    } else {
      setSortKey(key);
      setSortReversed(false);
    }
  };
  const arrow = (key: SortKey, up: string, down: string) =>
    sortKey === key ? (sortReversed ? down : up) : "";

  const visible = useMemo(() => {
    return sorted.filter((addon) => {
      const status = statusOf(addon);
      if (filter === "installed") return status !== "not-installed";
      if (filter === "update") return status === "update";
      return true;
    });
  }, [sorted, filter, statusOf]);

  const changePath = async () => {
    const picked = await open({
      directory: true,
      title: "Select your World of Warcraft folder or its AddOns folder",
      defaultPath: addonsPath ?? undefined,
    });
    if (typeof picked !== "string") return;
    try {
      const resolved = await setAddonsPath(picked);
      setPath(resolved);
      setNotice(null);
      await refreshInstalled(resolved);
    } catch (err) {
      setNotice({ kind: "error", text: errorText(err) });
    }
  };

  const perform = async (
    verb: string,
    addon: AddonInfo,
    action: (path: string, names: string[]) => Promise<ActionResult[]>,
  ) => {
    if (!addonsPath) return;
    setBusyName(addon.name);
    setNotice(null);
    try {
      const results = await action(addonsPath, [addon.name]);
      setNotice(summarize(verb, results));
      await refreshInstalled(addonsPath);
    } catch (err) {
      setNotice({ kind: "error", text: errorText(err) });
    } finally {
      setBusyName(null);
    }
  };

  const install = (addon: AddonInfo) =>
    perform(statusOf(addon) === "update" ? "Updated" : "Installed", addon, installAddons);

  const uninstall = (addon: AddonInfo) => perform("Uninstalled", addon, uninstallAddons);

  const openAddon = openName ? (bundled.find((a) => a.name === openName) ?? null) : null;

  return (
    <main className="app">
      <header className="header">
        <div className="header-top">
          <h1>
            TK's Mod Manager <span className="short">TKMM</span>
          </h1>
          <div className="theme-toggle">
            <span className="path-label">Theme</span>
            <div className="segmented" role="group" aria-label="Color theme">
              {THEMES.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className={theme === item.id ? "seg active" : "seg"}
                  aria-pressed={theme === item.id}
                  onClick={() => pickTheme(item.id)}
                >
                  {item.label}
                </button>
              ))}
            </div>
          </div>
        </div>
        {appUpdate && (
          <div className="update-banner">
            <span>TK's Mod Manager {appUpdate.version} is available.</span>
            <button type="button" className="primary" onClick={updateApp} disabled={updatingApp}>
              {updatingApp ? "Installing..." : "Install and restart"}
            </button>
          </div>
        )}
        {!openAddon && (
          <div className="path-row">
            <span className="path-label">AddOns folder</span>
            <span className={addonsPath ? "path" : "path missing"} title={addonsPath ?? undefined}>
              {addonsPath ?? "Not found. Choose your World of Warcraft folder."}
            </span>
            <button type="button" onClick={changePath} disabled={busy}>
              Change
            </button>
          </div>
        )}
      </header>

      {!openAddon && (
      <div className="toolbar">
        <span className="path-label">Show</span>
        <div className="segmented" role="group" aria-label="Filter addons">
          {FILTERS.map((item) => (
            <button
              key={item.id}
              type="button"
              className={filter === item.id ? "seg active" : "seg"}
              aria-pressed={filter === item.id}
              onClick={() => setFilter(item.id)}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>
      )}

      {openAddon ? (
        <AddonPage addon={openAddon} onBack={() => setOpenName(null)} />
      ) : (
      <section className="list">
        <div className="row head">
          <span aria-hidden="true" />
          <span>
            <button
              type="button"
              className={sortKey === "name" ? "sort-head active" : "sort-head"}
              onClick={() => setSortKey("name")}
              title="Sort A to Z"
            >
              Addon {sortKey === "name" ? "▲" : ""}
            </button>
          </span>
          <span>Latest</span>
          <span>Installed</span>
          <span>
            <button
              type="button"
              className={sortKey === "updated" ? "sort-head active" : "sort-head"}
              onClick={() => pickSort("updated")}
              title="Sort newest first. Click again for oldest first."
            >
              Last updated {arrow("updated", "▼", "▲")}
            </button>
          </span>
          <span>
            <button
              type="button"
              className={sortKey === "action" ? "sort-head active" : "sort-head"}
              onClick={() => pickSort("action")}
              title="Sort by action: Update, Installed, Install. Click again to reverse."
            >
              Action {arrow("action", "▲", "▼")}
            </button>
          </span>
        </div>
        {visible.map((addon) => {
          const status = statusOf(addon);
          const isBusy = busyName === addon.name;
          const isInstalled = installed.has(addon.name);
          const installLabel = isBusy
            ? "Working..."
            : status === "not-installed"
              ? "Install"
              : status === "update"
                ? "Update"
                : "Up to date";
          return (
            <div className="row" key={addon.name}>
              {addon.iconPath ? (
                <img className="icon" src={convertFileSrc(addon.iconPath)} alt="" />
              ) : (
                <span className="icon placeholder" aria-hidden="true" />
              )}
              <button
                type="button"
                className="info info-toggle"
                title="Open addon"
                onClick={() => setOpenName(addon.name)}
              >
                <span className="name">{displayName(addon)}</span>
                <span className="one-liner">{clipOneLiner(addon.oneLiner)}</span>
              </button>
              <span>{addon.version ?? "-"}</span>
              <span className="installed-cell">
                <span>{installed.get(addon.name)?.version ?? "-"}</span>
                <span className={`status ${status}`}>{STATUS_LABEL[status]}</span>
              </span>
              <span className="updated">{formatUpdated(addon.updatedAt)}</span>
              <span className="row-actions">
                <button
                  type="button"
                  className="row-btn primary"
                  onClick={() => install(addon)}
                  disabled={busy || !addonsPath || status === "current"}
                >
                  {installLabel}
                </button>
                <button
                  type="button"
                  className="row-btn"
                  onClick={() => uninstall(addon)}
                  disabled={busy || !addonsPath || !isInstalled}
                >
                  Uninstall
                </button>
              </span>
            </div>
          );
        })}
        {bundled.length === 0 && <p className="empty">No addons are bundled with this build.</p>}
        {bundled.length > 0 && visible.length === 0 && (
          <p className="empty">No addons match this filter.</p>
        )}
      </section>
      )}

      {notice && (
        <footer className="footer">
          <p className={`notice ${notice.kind}`}>{notice.text}</p>
        </footer>
      )}
    </main>
  );
}
