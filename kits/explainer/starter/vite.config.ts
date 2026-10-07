import { defineConfig } from 'vite';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { readFileSync } from 'node:fs';

/** The explainer kit is imported as TypeScript source; dedupe keeps one gsap. */
const KIT = process.env.EXPLAINER_KIT ?? join(homedir(), 'agents/kits/explainer');
const CUT = process.env.CUTAWAY_KIT ?? join(homedir(), 'agents/kits/cutaway');
const cert = (f: string): Buffer => readFileSync(resolve(join(homedir(), 'agents/research/2026-09-24/T71/stack/web/cert'), f));
export default defineConfig({
  base: './',
  resolve: {
    alias: [{ find: /^explainer-kit$/, replacement: `${KIT}/src/index.ts` }, { find: /^explainer-kit\/cutaway$/, replacement: `${KIT}/adapters/cutaway/index.ts` },
      { find: /^cutaway-kit$/, replacement: `${CUT}/src/index.ts` }, { find: /^cutaway-kit\/(.*)$/, replacement: `${CUT}/src/$1` }],
    dedupe: ['gsap', 'three'],
  },
  server: { host: '127.0.0.1', port: 18933, strictPort: true, https: { key: cert('key.pem'), cert: cert('cert.pem') }, fs: { allow: ['.', KIT, CUT] }, watch: { ignored: ['**/dist/**', '**/out/**'] } },
  build: { target: 'es2022', outDir: 'dist', assetsInlineLimit: 0, chunkSizeWarningLimit: 4000 },
});
