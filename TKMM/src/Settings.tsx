import { useEffect, useState } from "react";
import { THEMES, loadTheme, saveTheme, type ThemeId } from "./themes";

export function SettingsPage({ onBack }: { onBack: () => void }) {
  const [theme, setTheme] = useState<ThemeId>(loadTheme);

  const pick = (id: ThemeId) => {
    setTheme(id);
    saveTheme(id);
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onBack();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onBack]);

  return (
    <section className="addon-page">
      <div className="addon-page-top">
        <button type="button" className="back-button" onClick={onBack} title="Back to addons (Esc)">
          ← Back to addons
        </button>
      </div>
      <h2 className="settings-title">Settings</h2>
      <div className="settings-row">
        <label htmlFor="theme-select" className="path-label">
          Theme
        </label>
        <select
          id="theme-select"
          value={theme}
          onChange={(event) => pick(event.target.value as ThemeId)}
        >
          {THEMES.map((item) => (
            <option key={item.id} value={item.id}>
              {item.label}
            </option>
          ))}
        </select>
      </div>
    </section>
  );
}
