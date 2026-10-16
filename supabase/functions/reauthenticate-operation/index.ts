import { createReauthenticationHandler } from './handler.mjs';
function key(bundle: string, legacy: string): string {
 try { const value=JSON.parse(Deno.env.get(bundle) ?? '{}')?.default; if(typeof value==='string'&&value)return value; } catch { /* Missing keys fail closed. */ }
 return Deno.env.get(legacy) ?? '';
}
Deno.serve(createReauthenticationHandler({
 baseUrl:Deno.env.get('SUPABASE_URL'),
 publicKey:key('SUPABASE_PUBLISHABLE_KEYS','SUPABASE_ANON_KEY'),
 serviceKey:key('SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY'),
}));
