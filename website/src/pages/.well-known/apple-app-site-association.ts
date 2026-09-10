import { appleAssociation, readSiteConfig } from '../../lib/config.mjs';
export function GET() {
  return new Response(JSON.stringify(appleAssociation(readSiteConfig())), { headers: { 'Content-Type': 'application/json' } });
}
