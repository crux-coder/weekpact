export function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
