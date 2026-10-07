import { defineConfig } from 'vite';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { readFileSync } from 'node:fs';

/** The explainer kit is imported as TypeScript source; dedupe keeps one gsap. */
const KIT = process.env.EXPLAINER_KIT ?? join(homedir(), 'agents/kits/explainer');
const cert = (f: string): Buffer => readFileSync(resolve(join(homedir(), 'agents/research/2026-09-24/T71/stack/web/cert'), f));
export default defineConfig({
  base: './',
  resolve: {
    alias: [{ find: /^explainer-kit$/, replacement: `${KIT}/src/index.ts` }, { find: /^explainer-kit\/cutaway$/, replacement: `${KIT}/adapters/cutaway/index.ts` }],
    dedupe: ['gsap', 'three'],
  },
  server: { host: '127.0.0.1', port: 18932, strictPort: true, https: { key: cert('key.pem'), cert: cert('cert.pem') }, fs: { allow: ['.', KIT] }, watch: { ignored: ['**/dist/**', '**/out/**'] } },
  build: { target: 'es2022', outDir: 'dist', assetsInlineLimit: 0, chunkSizeWarningLimit: 4000 },
});
