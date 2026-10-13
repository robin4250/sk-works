import { createRateFetchHandler } from './handler.ts';

Deno.serve(createRateFetchHandler({env: (name) => Deno.env.get(name)}));
