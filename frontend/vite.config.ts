import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],

  preview: {
    allowedHosts: ['orderkeeper.razs.dev'],
  },

  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    env: {
      VITE_RPC_URL: 'http://localhost:8545',
      VITE_CONTRACT_ADDRESS: '0x0000000000000000000000000000000000000000',
      VITE_WETH_ADDRESS: '0x0000000000000000000000000000000000000001',
      VITE_QUOTE_TOKEN_ADDRESS: '0x0000000000000000000000000000000000000002',
      VITE_INDEXER_URL: 'http://localhost:3001',
    },
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/**/*.test.{ts,tsx}', 'src/main.tsx'],
    },
  },
})