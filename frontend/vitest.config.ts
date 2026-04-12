import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// Vitest config mirrors vite.config.ts so tests run under the same
// module resolution and JSX setup as the app itself.
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/__tests__/setup.ts"],
  },
});
