import { ExternalLink, Monitor, Moon, RefreshCw, Sun, X } from "lucide-react";
import { useForelStore } from "../store";
import { Theme, useSettings } from "../store/settings";

const THEME_OPTIONS: { value: Theme; label: string; icon: typeof Sun }[] = [
  { value: "system", label: "System", icon: Monitor },
  { value: "light", label: "Light", icon: Sun },
  { value: "dark", label: "Dark", icon: Moon },
];

export default function Settings({ onClose }: { onClose: () => void }) {
  const { theme, setTheme } = useSettings();
  const { updateStatus, updateInfo, checkForUpdates } = useForelStore((s) => ({
    updateStatus: s.updateStatus,
    updateInfo: s.updateInfo,
    checkForUpdates: s.checkForUpdates,
  }));

  // Triggered by the tray "Check for Updates…" item — handled in App.tsx.

  const updateLabel = () => {
    switch (updateStatus) {
      case "checking": return "Checking…";
      case "up-to-date": return `Up to date · v${updateInfo?.current_version ?? ""}`;
      case "available": return `v${updateInfo?.latest_version} available`;
      case "error": return "Check failed";
      default: return null;
    }
  };

  return (
    <div
      className="editor-overlay"
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div className="settings-panel">
        <header className="settings-header">
          <h2 className="settings-title">Settings</h2>
          <button className="editor-close" onClick={onClose} title="Close">
            <X size={16} />
          </button>
        </header>

        <section className="settings-section">
          <div className="settings-row">
            <div className="settings-label">
              <span className="settings-label-title">Appearance</span>
              <span className="settings-label-sub">
                Match the system or pick a fixed theme.
              </span>
            </div>
            <div className="segmented">
              {THEME_OPTIONS.map(({ value, label, icon: Icon }) => (
                <button
                  key={value}
                  className={`segmented-option${theme === value ? " active" : ""}`}
                  onClick={() => setTheme(value)}
                  title={label}
                >
                  <Icon size={13} />
                  <span>{label}</span>
                </button>
              ))}
            </div>
          </div>
        </section>

        <section className="settings-section">
          <div className="settings-about">
            <span className="settings-about-name">Forel</span>
            <span className="settings-about-version">Version 0.1.0 · alpha</span>
            <span className="settings-about-desc">
              Open-source file automation for macOS.
            </span>
            <div className="settings-update-row">
              <button
                className="settings-update-btn"
                onClick={() => void checkForUpdates()}
                disabled={updateStatus === "checking"}
                title="Check for updates"
              >
                <RefreshCw size={12} className={updateStatus === "checking" ? "spinning" : ""} />
                <span>Check for updates</span>
              </button>
              {updateLabel() && (
                <span className={`settings-update-status settings-update-status--${updateStatus}`}>
                  {updateLabel()}
                </span>
              )}
              {updateStatus === "available" && updateInfo?.release_url && (
                <a
                  className="settings-update-link"
                  href={updateInfo.release_url}
                  target="_blank"
                  rel="noreferrer"
                >
                  <ExternalLink size={11} />
                  <span>Download</span>
                </a>
              )}
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
