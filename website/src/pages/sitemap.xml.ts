import { readSiteConfig } from '../lib/config.mjs';
export function GET() {
  const { siteUrl } = readSiteConfig();
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>${siteUrl}/</loc></url><url><loc>${siteUrl}/privacy/</loc></url><url><loc>${siteUrl}/support/</loc></url></urlset>`, { headers: { 'Content-Type': 'application/xml' } });
}
