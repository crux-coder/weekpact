import { androidAssociation, readSiteConfig } from '../../lib/config.mjs';
export function GET() {
  return new Response(JSON.stringify(androidAssociation(readSiteConfig())), { headers: { 'Content-Type': 'application/json' } });
}
