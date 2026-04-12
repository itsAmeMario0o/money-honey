import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Proxy /api calls to the FastAPI dev server so the frontend and backend
// feel like one origin during local development.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: true,
      },
    },
  },
});
