import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

// The SPA talks to the API through the same origin in production (nginx proxy).
// During local development Vite proxies these paths to the API to avoid CORS.
const apiTarget = process.env.VITE_DEV_API_TARGET ?? 'http://localhost:8080';

const proxy = {
  '/api': { target: apiTarget, changeOrigin: true },
  '/health': { target: apiTarget, changeOrigin: true },
};

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy,
  },
  preview: {
    port: 4173,
    strictPort: true,
    proxy,
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.ts'],
    css: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/main.tsx', 'src/setupTests.ts', 'src/vite-env.d.ts'],
      thresholds: {
        lines: 80,
      },
    },
  },
});
