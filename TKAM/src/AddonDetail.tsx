import { useEffect, useState, type ReactNode } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import type { AddonInfo } from "./api";

function inlineMarkdown(text: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  const pattern = /`([^`]+)`|\*\*([^*]+)\*\*/g;
  let last = 0;
  let match: RegExpExecArray | null;
  let key = 0;
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > last) nodes.push(text.slice(last, match.index));
    if (match[1] !== undefined) nodes.push(<code key={key}>{match[1]}</code>);
    else nodes.push(<strong key={key}>{match[2]}</strong>);
    key += 1;
    last = match.index + match[0].length;
  }
  if (last < text.length) nodes.push(text.slice(last));
  return nodes;
}

export function AddonDetail({ addon }: { addon: AddonInfo }) {
  const [view, setView] = useState<"about" | "releases">("about");
  const [picked, setPicked] = useState<string | null>(null);
  const release = addon.releases.find((item) => item.version === picked) ?? null;

  if (view === "releases") {
    return (
      <div className="expand-panel">
        <button
          type="button"
          className="link back"
          onClick={() => {
            setView("about");
            setPicked(null);
          }}
        >
          Description
        </button>
        <div className="releases">
          <div>
            <h3>Release notes</h3>
            {addon.releases.length === 0 ? (
              <p className="prompt">No release notes in tkam.config.</p>
            ) : (
              <ul className="version-list">
                {addon.releases.map((item) => (
                  <li key={item.version}>
                    <button
                      type="button"
                      className={item.version === picked ? "version on" : "version"}
                      aria-pressed={item.version === picked}
                      onClick={() => setPicked(item.version)}
                    >
                      {item.version}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div className="release-notes">
            {release ? (
              <ul>
                {release.notes.map((note) => (
                  <li key={note}>{inlineMarkdown(note)}</li>
                ))}
              </ul>
            ) : (
              addon.releases.length > 0 && <p className="prompt">Choose a version.</p>
            )}
          </div>
        </div>
      </div>
    );
  }

  const paragraphs = addon.description?.split(/\n{2,}/).filter((part) => part.length > 0) ?? [];
  const commands = addon.commands ?? [];

  return (
    <div className="expand-panel">
      <h3>One Liner</h3>
      {addon.oneLiner ? (
        <p>{addon.oneLiner}</p>
      ) : (
        <p className="prompt">No one-liner in tkam.config.</p>
      )}
      <h3>Description</h3>
      {paragraphs.length > 0 ? (
        paragraphs.map((paragraph, index) => <p key={index}>{inlineMarkdown(paragraph)}</p>)
      ) : (
        <p className="prompt">No description in tkam.config.</p>
      )}
      <h3>Features</h3>
      {addon.features.length > 0 ? (
        <ul className="features">
          {addon.features.map((feature) => (
            <li key={feature}>{inlineMarkdown(feature)}</li>
          ))}
        </ul>
      ) : (
        <p className="prompt">No features in tkam.config.</p>
      )}
      <h3>Commands</h3>
      {commands.length > 0 ? (
        <ul className="commands">
          {commands.map((command) => (
            <li key={command}>{inlineMarkdown(command)}</li>
          ))}
        </ul>
      ) : (
        <p className="prompt">No commands in tkam.config.</p>
      )}
      <button type="button" className="link" onClick={() => setView("releases")}>
        Release notes
      </button>
    </div>
  );
}

/** Full-window view for one addon. Replaces the list until Back is pressed. */
export function AddonPage({ addon, onBack }: { addon: AddonInfo; onBack: () => void }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onBack();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onBack]);

  return (
    <div className="addon-page">
      <div className="addon-page-top">
        <button type="button" className="back-button" onClick={onBack} title="Back to addons (Esc)">
          ← Back to addons
        </button>
      </div>
      <header className="addon-page-header">
        {addon.iconPath ? (
          <img className="icon" src={convertFileSrc(addon.iconPath)} alt="" />
        ) : (
          <span className="icon placeholder" aria-hidden="true" />
        )}
        <div className="info">
          <span className="name">{addon.publicName}</span>
        </div>
      </header>
      <div className={addon.screenshotPath ? "addon-page-body" : "addon-page-body single"}>
        <AddonDetail key={addon.name} addon={addon} />
        {addon.screenshotPath && (
          <figure className="addon-shot">
            <img src={convertFileSrc(addon.screenshotPath)} alt={`${addon.publicName} screenshot`} />
          </figure>
        )}
      </div>
    </div>
  );
}
