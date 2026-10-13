import { fetchOfficialRates } from './official_rates.ts';

export type HandlerDependencies = {
  env: (name: string) => string | undefined;
  fetcher?: typeof fetch;
  fetchRates?: typeof fetchOfficialRates;
  now?: () => Date;
};
export function createRateFetchHandler(dependencies: HandlerDependencies): (req: Request) => Promise<Response> {
const fetch = dependencies.fetcher ?? globalThis.fetch;
const fetchRates = dependencies.fetchRates ?? fetchOfficialRates;

function key(name: string, fallback: string): string {
  const raw = dependencies.env(name);
  if (raw) { const value = JSON.parse(raw).default; if (typeof value === 'string') return value; }
  const value = dependencies.env(fallback);
  if (!value) throw new Error('Server configuration unavailable');
  return value;
}
function reply(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {status, headers: {'Content-Type': 'application/json'}});
}
function month(value: unknown): string {
  if (typeof value !== 'string' || !/^20\d{2}-(0[1-9]|1[0-2])-01$/.test(value)) throw new Error('Invalid month');
  return value;
}
const labels: Record<string,string> = {health_insurance:'健康保険料',nursing_insurance:'介護保険料',pension_insurance:'厚生年金保険',employment_insurance:'雇用保険料',child_support:'子ども・子育て支援金'};
return async (req: Request) => {
  if (req.method !== 'POST') return reply({error:'POST required'},405);
  try {
    const base = dependencies.env('SUPABASE_URL');
    if (!base) throw new Error('Server configuration unavailable');
    const authorization = req.headers.get('authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return reply({error:'Authentication required'},401);
    const publicKey = key('SUPABASE_PUBLISHABLE_KEYS','SUPABASE_ANON_KEY');
    const userHeaders = {apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'};
    const userResponse = await fetch(`${base}/auth/v1/user`,{headers:userHeaders,signal:AbortSignal.timeout(10000)});
    if (!userResponse.ok) return reply({error:'Authentication required'},401);
    const user = await userResponse.json();
    if (typeof user.id !== 'string') return reply({error:'Authentication required'},401);
    const reader = req.body?.getReader();
    if (!reader) return reply({error:'Request body required'},400);
    let size = 0; const chunks: Uint8Array[] = [];
    for (;;) {
      const {done,value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 2048) { await reader.cancel(); return reply({error:'Request too large'},400); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset=0;
    for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.byteLength; }
    let body: Record<string,unknown>;
    try { body = JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)); }
    catch { return reply({error:'Invalid request'},400); }
    if (!body || typeof body !== 'object' || Array.isArray(body)) return reply({error:'Invalid request'},400);
    if (typeof body.company_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.company_id)) return reply({error:'Invalid company'},400);
    const insurance = month(body.insurance_month), payroll = month(body.payroll_month), payment = month(body.payment_month);
    const monthIndex = (m: string) => Number(m.slice(0,4))*12+Number(m.slice(5,7));
    if (Math.abs(monthIndex(insurance)-monthIndex(payroll))>1 || monthIndex(payment)<monthIndex(payroll) || monthIndex(payment)>monthIndex(payroll)+1) return reply({error:'対象月・給与支払月を確認してください。'},400);
    const now = dependencies.now?.() ?? new Date();
    const currentMonth = new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Tokyo',year:'numeric',month:'2-digit'}).format(now)+'-01';
    if (insurance > currentMonth) return reply({error:'将来の保険月は取得対象外です。'},400);
    async function read() {
      const response = await fetch(`${base}/rest/v1/rpc/read_company_payroll_rates`,{method:'POST',headers:userHeaders,body:JSON.stringify({p_company_id:body.company_id}),signal:AbortSignal.timeout(10000)});
      if (!response.ok) throw new Error('Rate access unavailable');
      return await response.json();
    }
    const initial = await read();
    if (initial.can_edit !== true) return reply({error:'会社管理者のみ取得できます。'},403);
    if (!initial.company_scope || !Number.isSafeInteger(initial.company_scope.version) || initial.company_scope.version < 1) return reply({error:'先に会社の適用条件を保存してください。'},400);
    const fetched = await fetchRates(initial.company_scope.value,{now,fetcher:fetch});
    if (!fetched.rates.length) return reply({error:'会社条件に合う公式料率を取得できませんでした。'},422);
    const values = fetched.rates.map(rate => {
      if (insurance < rate.insuranceMonth) throw new Error('保険適用月が公式料率の開始月より前です。');
      return {kind:rate.kind,label:labels[rate.kind],total:rate.total,employee:rate.employee,employer:rate.employer,
        insurance_month:insurance,payroll_month:payroll,payment_month:payment,source:{...rate.source,applicability:{...rate.source.applicability,
          scope_version:String(initial.company_scope.version),
          ...Object.fromEntries(Object.entries(initial.company_scope.value).filter(([,v])=>typeof v === 'string'))}}};
    });
    const latest = await read();
    if (latest.can_edit !== true || latest.company_scope?.version !== initial.company_scope.version) return reply({error:'会社条件が変更されました。再読み込みしてください。'},409);
    const serviceKey = key('SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
    const headers: Record<string,string> = {apikey:serviceKey,'Content-Type':'application/json'};
    if (!serviceKey.startsWith('sb_secret_')) headers.Authorization = `Bearer ${serviceKey}`;
    const saved = await fetch(`${base}/rest/v1/rpc/publish_official_payroll_rate_candidates`,{method:'POST',headers,
      body:JSON.stringify({p_company_id:body.company_id,p_actor_id:user.id,p_scope_version:initial.company_scope.version,p_values:values}),signal:AbortSignal.timeout(10000)});
    if (!saved.ok) throw new Error('Candidate publication failed');
    return reply({ok:true,checked_at:fetched.checkedAt,warnings:fetched.warnings});
  } catch (_) {
    // Never return credentials, upstream bodies or internal SQL messages.
    return reply({error:'公式資料を確認できませんでした。現在の設定は変更していません。会社条件・適用月と接続を確認し、再取得してください。'},422);
  }
};
}
