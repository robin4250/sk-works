import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createLineWebhookHandler } from "./handler.mjs";

// LINE verifies HMAC itself; deploy this webhook with verify_jwt=false.
Deno.serve(createLineWebhookHandler({ env: (name: string) => Deno.env.get(name) }));
