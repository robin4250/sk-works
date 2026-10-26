// Review-only Edge entrypoint. No deployment or provider configuration implied.
import { createHandler } from './handler.mjs';
Deno.serve(createHandler(Deno.env.toObject()));
