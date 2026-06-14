import { Settings as SettingsIcon } from "lucide-react";
import { useEffect, useState } from "react";
import RuleList from "./components/RuleList";
import Settings from "./components/Settings";
import Sidebar from "./components/Sidebar";
import { useForelStore } from "./store";
import "./store/settings"; // applies the persisted theme on load
import "./App.css";
import forelIcon from "./assets/forel-icon.png";
import { Events } from "@wailsio/runtime";

export default function App() {
  const fetchFolders = useForelStore((s) => s.fetchFolders);
  const checkForUpdates = useForelStore((s) => s.checkForUpdates);
  const [showSettings, setShowSettings] = useState(false);

  useEffect(() => {
    void fetchFolders();
  }, [fetchFolders]);

  // ⌘, opens Settings, like a native macOS app.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey && e.key === ",") {
        e.preventDefault();
        setShowSettings(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // Tray "Check for Updates…" → open Settings and trigger check.
  useEffect(() => {
    const off = Events.On("tray:check-updates", () => {
      setShowSettings(true);
      void checkForUpdates();
    });
    return () => off();
  }, [checkForUpdates]);

  return (
    <div className="app">
      <div className="titlebar">
        <div className="titlebar-brand">
          <img className="titlebar-icon" src={forelIcon} alt="" />
          <span className="titlebar-title">Forel</span>
        </div>
        <button
          className="titlebar-btn"
          onClick={() => setShowSettings(true)}
          title="Settings (⌘,)"
        >
          <SettingsIcon size={15} />
        </button>
      </div>

      <div className="layout">
        <Sidebar />
        <RuleList />
      </div>

      {showSettings && <Settings onClose={() => setShowSettings(false)} />}
    </div>
  );
}
