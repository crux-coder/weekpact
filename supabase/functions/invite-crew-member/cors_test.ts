import { corsHeaders } from "./cors.ts";

Deno.test("preflight permits every header in a Flutter invite request", () => {
  const response = new Response("ok", { headers: corsHeaders() });
  const allowed = response.headers.get("Access-Control-Allow-Headers")!
    .split(",").map((value) => value.trim().toLowerCase());
  for (
    const header of ["authorization", "apikey", "content-type", "x-client-info"]
  ) {
    if (!allowed.includes(header)) {
      throw new Error(`Preflight blocks ${header}`);
    }
  }
  if (!response.headers.get("Access-Control-Allow-Methods")?.includes("POST")) {
    throw new Error("Preflight blocks POST");
  }
});
