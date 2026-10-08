import { createHandler } from './handler.mjs';
import { intakeConfiguration } from './intake_configuration.mjs';
import { createGoogleCredentialStore } from './google_credential_store.mjs';
const env = (k: string) => Deno.env.get(k) ?? '';
Deno.serve(createHandler({
  authenticate: async (req: Request) => {
    const authorization = req.headers.get('authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return null;
    // Supabase Auth verifies the token before any claims are used.
    const r = await fetch(env('SUPABASE_URL') + '/auth/v1/user', {
      headers: { apikey: env('SUPABASE_SERVICE_ROLE_KEY'), Authorization: authorization },
      signal: AbortSignal.timeout(10000),
    });
    if (!r.ok) return null;
    const user = await r.json();
    const part = authorization.slice(7).split('.')[1].replace(/-/g,'+').replace(/_/g,'/');
    const claims = JSON.parse(atob(part.padEnd(Math.ceil(part.length/4)*4,'=')));
    return {user,claims};
  },
  configuration: () => intakeConfiguration(env),
  status: async (user: string, session: string) => {
    const r = await fetch(env('SUPABASE_URL') + '/rest/v1/rpc/get_account_deletion_status', {
      method:'POST', signal:AbortSignal.timeout(10000),
      headers: {apikey:env('SUPABASE_SERVICE_ROLE_KEY'),Authorization:'Bearer '+env('SUPABASE_SERVICE_ROLE_KEY'),'Content-Type':'application/json'},
      body: JSON.stringify({p_user:user,p_session:session}),
    });
    if (!r.ok) throw Error('unavailable');
    return await r.json();
  },
  prepareGoogleCredential: async (user: any, session: string, token?: string) => {
    if (!user.identities?.some((i: any) => i.provider === 'google')) {
      if (token !== undefined) throw Error('unexpected_provider_credential');
      return null;
    }
    return createGoogleCredentialStore({
      rpc: async () => { throw Error('intake_cannot_read_credentials'); },
      keyHex: env('ACCOUNT_DELETION_CREDENTIAL_KEY'),
      clientId: env('GOOGLE_SIGN_IN_CLIENT_ID'),
      clientSecret: env('GOOGLE_SIGN_IN_CLIENT_SECRET'),
    }).prepareIntake(user,session,token);
  },
  reserve: async (user: string, session: string, policy: string, days: number, credential?: unknown) => {
    const name = credential ? 'request_account_deletion_with_google' : 'request_account_deletion';
    const r = await fetch(env('SUPABASE_URL') + '/rest/v1/rpc/' + name, {
      method:'POST', signal:AbortSignal.timeout(10000),
      headers: {apikey:env('SUPABASE_SERVICE_ROLE_KEY'),Authorization:'Bearer '+env('SUPABASE_SERVICE_ROLE_KEY'),'Content-Type':'application/json'},
      body: JSON.stringify({p_user:user,p_session:session,p_policy:policy,p_days:days,
        ...(credential ? {p_credential:credential} : {})}),
    });
    if (!r.ok) throw Error('unavailable');
    return await r.json();
  },
}));
