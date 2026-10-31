import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Deployed to GitHub Pages as a project site: anuragdevcode.github.io/Tangent
const BASE = '/Tangent/'

export default defineConfig({
  base: BASE,
  plugins: [react()],
  build: {
    target: 'es2022',
    chunkSizeWarningLimit: 900,
  },
})
