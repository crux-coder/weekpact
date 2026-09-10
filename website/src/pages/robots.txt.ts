import { readSiteConfig } from '../lib/config.mjs';
export function GET() {
  const { siteUrl } = readSiteConfig();
  return new Response(`User-agent: *\nAllow: /\n\nSitemap: ${siteUrl}/sitemap.xml\n`, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}
