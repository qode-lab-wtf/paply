import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

// HINWEIS: Diese Vite-Konfiguration ist für eine ältere React-UI, die NICHT MEHR VERWENDET wird.
// Die aktuelle App verwendet die HTML-Dateien (dashboard.html, recording.html, etc.) direkt.
// Der `dist/` Ordner wird von electron-builder verwendet, daher baut Vite nach `vite-dist/`.
export default defineConfig({
  plugins: [react()],
  root: path.resolve(__dirname, "src"),
  build: {
    // Verwende einen separaten Ordner, um Konflikte mit electron-builder zu vermeiden
    outDir: path.resolve(__dirname, "vite-dist"),
    emptyOutDir: true,
  },
  server: {
    port: 5174,
  },
});
