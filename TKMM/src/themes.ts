export type ThemeId = "dark" | "light" | "midnight" | "forest";

export const THEMES: { id: ThemeId; label: string }[] = [
  { id: "dark", label: "Dark" },
  { id: "light", label: "Light" },
  { id: "midnight", label: "Midnight" },
  { id: "forest", label: "Forest" },
];

export const DEFAULT_THEME: ThemeId = "dark";

const STORAGE_KEY = "tkmm.theme";

function isThemeId(value: string | null): value is ThemeId {
  return THEMES.some((theme) => theme.id === value);
}

export function loadTheme(): ThemeId {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return isThemeId(stored) ? stored : DEFAULT_THEME;
  } catch {
    return DEFAULT_THEME;
  }
}

export function applyTheme(id: ThemeId): void {
  document.documentElement.dataset.theme = id;
}

export function saveTheme(id: ThemeId): void {
  applyTheme(id);
  try {
    localStorage.setItem(STORAGE_KEY, id);
  } catch {
    // Storage can be unavailable; the theme still applies for this session.
  }
}
