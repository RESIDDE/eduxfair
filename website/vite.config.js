import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { resolve } from 'node:path';

// Multi-page: every legal document is a real HTML file at its own path
// (/privacy/, /terms/, /guidelines/), so it works on any static host with no
// rewrite rules — App Store Connect links straight to /privacy.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5180 },
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, 'index.html'),
        privacy: resolve(import.meta.dirname, 'privacy/index.html'),
        terms: resolve(import.meta.dirname, 'terms/index.html'),
        guidelines: resolve(import.meta.dirname, 'guidelines/index.html'),
        deleteAccount: resolve(import.meta.dirname, 'delete-account/index.html'),
      },
    },
  },
});
