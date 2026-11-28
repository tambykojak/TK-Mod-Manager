import { useEffect } from "react";
import { THEMES, type Theme } from "./theme";

type Props = {
  theme: Theme;
  onThemeChange: (theme: Theme) => void;
  onClose: () => void;
};

export function SettingsDialog({ theme, onThemeChange, onClose }: Props) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="modal-head">
          <h2 id="settings-title">Settings</h2>
          <button type="button" className="icon-button" onClick={onClose} aria-label="Close settings">
            <CloseIcon />
          </button>
        </div>

        <section className="setting">
          <h3>Theme</h3>
          <div className="theme-grid" role="group" aria-label="Color theme">
            {THEMES.map((item) => (
              <button
                key={item.id}
                type="button"
                className={theme === item.id ? "theme-option active" : "theme-option"}
                aria-pressed={theme === item.id}
                onClick={() => onThemeChange(item.id)}
              >
                <span className="theme-swatch" style={{ background: item.swatch }}>
                  <span className="theme-swatch-dot" style={{ background: item.accent }} />
                </span>
                <span>{item.label}</span>
              </button>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}

export function GearIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <path
        d="M19.4 13.5a7.7 7.7 0 0 0 0-3l2-1.6-2-3.4-2.4 1a7.6 7.6 0 0 0-2.6-1.5L14 3.5h-4l-.4 2.5a7.6 7.6 0 0 0-2.6 1.5l-2.4-1-2 3.4 2 1.6a7.7 7.7 0 0 0 0 3l-2 1.6 2 3.4 2.4-1a7.6 7.6 0 0 0 2.6 1.5l.4 2.5h4l.4-2.5a7.6 7.6 0 0 0 2.6-1.5l2.4 1 2-3.4-2-1.6Z"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="M6 6l12 12M18 6L6 18" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}
