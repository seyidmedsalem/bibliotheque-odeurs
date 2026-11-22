import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// En développement, /api et /ws sont redirigés vers le backend FastAPI (port 8000).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:8000",
      "/docs": "http://localhost:8000",
      "/openapi.json": "http://localhost:8000",
      "/ws": { target: "ws://localhost:8000", ws: true },
    },
  },
});
