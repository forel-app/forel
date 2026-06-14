import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Wails serves the dev frontend on this port (see Taskfile VITE_PORT).
  // Bind to IPv4 explicitly — Wails' asset proxy dials 127.0.0.1, and a default
  // "localhost" bind can resolve to IPv6 (::1) only, causing "connection refused".
  server: {
    host: "127.0.0.1",
    port: 9245,
    strictPort: true,
  },
});
