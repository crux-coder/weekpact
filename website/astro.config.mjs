import { defineConfig } from 'astro/config';
import { existsSync } from 'node:fs';
import { loadEnvFile } from 'node:process';
import { fileURLToPath } from 'node:url';
import { readSiteConfig } from './src/lib/config.mjs';

const envPath = fileURLToPath(new URL('.env', import.meta.url));
if (existsSync(envPath)) loadEnvFile(envPath);
const config = readSiteConfig();

export default defineConfig({
  site: config.siteUrl,
  output: 'static',
  trailingSlash: 'always',
  build: { inlineStylesheets: 'never' },
  devToolbar: { enabled: false },
});
