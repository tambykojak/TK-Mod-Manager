export const THEMES = [
  { id: "dark", label: "Dark", swatch: "#17151a", accent: "#f2c14e" },
  { id: "light", label: "Light", swatch: "#f6f3ec", accent: "#8a5f00" },
  { id: "midnight", label: "Midnight", swatch: "#0d1424", accent: "#7fb2ff" },
  { id: "forest", label: "Forest", swatch: "#131b15", accent: "#9fd47a" },
  { id: "sepia", label: "Sepia", swatch: "#f1e6cf", accent: "#7a4a1e" },
] as const;

export type Theme = (typeof THEMES)[number]["id"];

const DEFAULT_THEME: Theme = "dark";
const STORAGE_KEY = "tkmm.theme";

function isTheme(value: string | null): value is Theme {
  return THEMES.some((theme) => theme.id === value);
}

export function loadTheme(): Theme {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return isTheme(stored) ? stored : DEFAULT_THEME;
  } catch {
    return DEFAULT_THEME;
  }
}

export function applyTheme(theme: Theme): void {
  document.documentElement.dataset.theme = theme;
}

export function saveTheme(theme: Theme): void {
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Storage can be unavailable; the choice then lasts for this session only.
  }
}
