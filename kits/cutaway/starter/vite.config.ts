import { defineConfig } from 'vite';
import { homedir } from 'node:os';
import { join } from 'node:path';

/** The kits are imported as TypeScript source; dedupe keeps one three.js and one gsap. */
const KIT = process.env.CUTAWAY_KIT ?? join(homedir(), 'agents/kits/cutaway');
const ENGINE = process.env.EXPLAINER_KIT ?? join(homedir(), 'agents/kits/explainer');
export default defineConfig({
  base: './',
  resolve: { alias: [{ find: /^cutaway-kit$/, replacement: `${KIT}/src/index.ts` }, { find: /^cutaway-kit\/(.*)$/, replacement: `${KIT}/src/$1` }, { find: /^explainer-kit$/, replacement: `${ENGINE}/src/index.ts` }], dedupe: ['three', 'gsap'] },
  server: { host: '127.0.0.1', port: 18975, strictPort: false, fs: { allow: ['.', KIT, ENGINE] }, watch: { ignored: ['**/dist/**', '**/out/**'] } },
  build: { target: 'es2022', outDir: 'dist', assetsInlineLimit: 0, chunkSizeWarningLimit: 4000 },
});
