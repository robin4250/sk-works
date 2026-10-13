/** Official-source retrieval only. This module never applies or writes company settings. */
export type RateScope = { insurer: string; prefecture: string | null; employment_business: string | null };
export type OfficialRate = {
  kind: string; total: number; employee: number; employer: number;
  insuranceMonth: string; paymentMonth: string | null;
  source: { url: string; publisher: string; document_hash: string; applicability: Record<string, string> };
};
export const SOURCES = {
  healthIndex: 'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/rate_prefectures/',
  health: 'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/rate_prefectures/r08/',
  care: 'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/002/',
  child: 'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/003/',
  pension: 'https://www.nenkin.go.jp/service/kounen/hokenryo/ryogaku/ryogakuhyo/index.html',
  employmentIndex: 'https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000108634.html',
  employment: 'https://jsite.mhlw.go.jp/yamagata-roudoukyoku/koyouhoken-20260316.html',
} as const;
export const PREFECTURES = '北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県'.split(' ');
const fail = (detail: string): never => { throw new Error(`公式料率を確認できません: ${detail}`); };
export function plain(html: string): string {
  return html.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<!--[^]*?-->/g, '').replace(/<[^>]+>/g, ' ')
    .replace(/&#(x[0-9a-f]+|\d+);/gi, (_, code: string) => String.fromCodePoint(code[0].toLowerCase() === 'x' ? parseInt(code.slice(1), 16) : Number(code)))
    .replace(/&(?:nbsp|ensp|emsp);/g, ' ').replace(/&amp;/g, '&').normalize('NFKC').replace(/\s+/g, ' ').trim();
}
function compact(html: string): string { return plain(html).replace(/\s/g, ''); }
function percent(s: string): number {
  const match = /^(\d{1,2})(?:\.(\d{1,6}))?$/.exec(s);
  if (!match) return fail('数値形式');
  const n = Number(match[1]) * 1000000 + Number((match[2] ?? '').padEnd(6, '0'));
  if (n <= 0 || n > 30000000) return fail('料率範囲');
  return n;
}
function rows(html: string): string[][] {
  return [...html.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)].map(m =>
    [...m[1].matchAll(/<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(c => compact(c[1])));
}
export function parseHealth(html: string, year: number): Map<string, number> {
  const reiwa = year - 2018;
  const text = compact(html);
  if (!text.includes(`令和${reiwa}年度都道府県単位保険料率`) ||
      !text.includes(`令和${reiwa}年度の協会けんぽの保険料率は3月分(4月納付分)`)) fail('健康保険の年度・適用月');
  const tables = [...html.matchAll(/<table\b[^>]*>([\s\S]*?)<\/table>/gi)].map(m => rows(m[1]));
  const table = tables.find(t => t.some(r => r[0] === '北海道'));
  if (!table || !table.some(r => r[1] === `令和${reiwa - 1}年度` && r[3] === `令和${reiwa}年度`)) fail('健康保険表の列');
  const result = new Map<string, number>();
  for (const row of table!) {
    if (!PREFECTURES.includes(row[0])) continue;
    if (row.length !== 4 || !/^\d+(?:\.\d+)?%$/.test(row[3]) || result.has(row[0])) fail('都道府県の重複・形式');
    result.set(row[0], percent(row[3].slice(0, -1)));
  }
  if (result.size !== 47) fail('都道府県47件');
  return result;
}
export function parseGeneralRate(html: string, year: number, month: number): number {
  const section = compact(html).split('一般被保険者')[1]?.split('任意継続被保険者')[0];
  if (!section) return fail('一般被保険者の区分');
  const all = [...section.matchAll(/令和(\d+)年(\d+)月分\((\d+)月(?:\d+日)?納付(?:期限)?分\)から(\d+(?:\.\d+)?)%/g)];
  const matches = all.filter(m => Number(m[1]) + 2018 === year && Number(m[2]) === month && Number(m[3]) === month + 1);
  if (matches.length !== 1) return fail('一般被保険者の年度・適用月');
  return percent(matches[0][4]);
}
export function parsePension(html: string): number {
  const matches = [...compact(html).matchAll(/平成29年9月を最後に引上げが終了し、厚生年金保険料率は(\d+(?:\.\d+)?)%で固定されています/g)];
  if (matches.length !== 1) return fail('厚生年金の固定料率');
  return percent(matches[0][1]);
}
const businesses = { general: '一般の事業', agriculture_forestry_fisheries_sake: '農林水産・清酒製造の事業', construction: '建設の事業' };
export function parseEmployment(html: string, year: number): Record<string, {total: number; employee: number; employer: number}> {
  const text = compact(html), r = year - 2018;
  if (!text.includes(`適用期間:令和${r}年4月1日~令和${r + 1}年3月31日`) && !text.includes(`適用期間:令和${r}年4月1日～令和${r + 1}年3月31日`)) fail('雇用保険の適用期間');
  const table = rows(html);
  if (!table.some(row => row.length === 4 && row[1].includes('労働者負担') && row[2].includes('事業主負担') && row[3].includes('雇用保険料率'))) fail('雇用保険の負担列');
  const output: Record<string, {total: number; employee: number; employer: number}> = {};
  for (const [key, label] of Object.entries(businesses)) {
    const selected = table.filter(r => r[0] === label);
    if (selected.length !== 1 || selected[0].length !== 4) fail('雇用保険の事業区分');
    const numbers = selected[0].slice(1).map(s => { const m = /^(\d+(?:\.\d+)?)\/1,000$/.exec(s); if (!m) return fail('雇用保険の単位'); return percent(m[1]) / 10; });
    if (!numbers.every(Number.isSafeInteger) || numbers[0] + numbers[1] !== numbers[2]) fail('雇用保険の合計');
    output[key] = {employee: numbers[0], employer: numbers[1], total: numbers[2]};
  }
  return output;
}
export function verifyAnnualIndex(html: string, year: number, category: 'health' | 'employment'): void {
  const text = compact(html);
  const pattern = category === 'health' ? /令和(\d+)年度保険料率/g : /令和(\d+)年度の雇用保険料率/g;
  const years = [...text.matchAll(pattern)].map(m => Number(m[1]) + 2018).filter(y => y <= year);
  if (!years.length || Math.max(...years) !== year) fail('当年度の公式入口');
}
export async function fetchOfficialDocument(url: string, fetcher: typeof fetch = fetch, timeoutMs = 12000): Promise<{html: string; hash: string}> {
  // Exact sources only; redirects may only switch the same directory to index.html.
  const allowed = new Set<string>(Object.values(SOURCES));
  if (!allowed.has(url)) fail('取得先');
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    let target = url;
    for (let hop = 0; hop < 3; hop++) {
      const response = await fetcher(target, {redirect: 'manual', signal: controller.signal, headers: {Accept: 'text/html'}});
      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get('location');
        if (!location) fail('転送先');
        const next = new URL(location!, target);
        const original = new URL(url);
        const normalized = (p: string) => p.replace(/index\.html$/, '').replace(/\/$/, '');
        if (next.origin !== original.origin || next.search || next.hash || next.username || next.password || normalized(next.pathname) !== normalized(original.pathname)) fail('転送先');
        await response.body?.cancel(); target = next.href; continue;
      }
      if (!response.ok || !response.headers.get('content-type')?.includes('text/html')) fail('公式ページの応答');
      const maximum = 750000;
      if (Number(response.headers.get('content-length') ?? 0) > maximum) fail('資料サイズ');
      if (!response.body) fail('空の資料');
      const reader = response.body!.getReader(); const chunks: Uint8Array[] = []; let size = 0;
      try { for (;;) { const {done, value} = await reader.read(); if (done) break; size += value.byteLength; if (size > maximum) fail('資料サイズ'); chunks.push(value); } }
      catch (error) { await reader.cancel(); throw error; }
      const bytes = new Uint8Array(size); let offset = 0; for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))).map(n => n.toString(16).padStart(2, '0')).join('');
      return {html: new TextDecoder('utf-8', {fatal: true}).decode(bytes), hash};
    }
    return fail('転送回数');
  } finally { clearTimeout(timer); }
}
export async function fetchOfficialRates(scope: RateScope, options: {fetcher?: typeof fetch; now?: Date} = {}): Promise<{rates: OfficialRate[]; checkedAt: string; year: number; warnings: string[]}> {
  const now = options.now ?? new Date();
  const japaneseNow = new Date(now.getTime() + 9 * 3600000);
  const year = japaneseNow.getUTCFullYear(), month = japaneseNow.getUTCMonth() + 1;
  // The reviewed HTML adapters cover this fiscal year only. Never reuse old rates after rollover.
  if (year !== 2026 || month < 4) fail('対応する当年度資料の検証が必要です');
  if (!['kyokai', 'union', 'other', 'unconfigured'].includes(scope.insurer)) fail('加入保険者を設定してください');
  if (scope.insurer === 'kyokai' && !PREFECTURES.includes(scope.prefecture ?? '')) fail('都道府県を設定してください');
  if (!(scope.employment_business && Object.hasOwn(businesses, scope.employment_business))) fail('雇用保険の事業区分を設定してください');
  const keys: (keyof typeof SOURCES)[] = ['pension', 'employmentIndex', 'employment'];
  if (scope.insurer === 'kyokai') keys.push('healthIndex', 'health', 'care', 'child');
  const documents = Object.fromEntries(await Promise.all(keys.map(async key => [key, await fetchOfficialDocument(SOURCES[key], options.fetcher)])));
  verifyAnnualIndex(documents.employmentIndex.html, year, 'employment');
  const employment = parseEmployment(documents.employment.html, year)[scope.employment_business!];
  const rates: OfficialRate[] = []; const warnings: string[] = [];
  const add = (kind: string, key: keyof typeof SOURCES, total: number, insuranceMonth: string, paymentMonth: string | null, applicability: Record<string,string>, employee = total / 2, employer = total / 2) => {
    if (![total, employee, employer].every(Number.isSafeInteger)) fail('負担率の精度');
    rates.push({kind, total, employee, employer, insuranceMonth, paymentMonth, source: {url: SOURCES[key], publisher: key === 'pension' ? '日本年金機構' : key === 'employment' ? '厚生労働省 山形労働局' : '全国健康保険協会', document_hash: documents[key].hash, applicability: {...applicability, year: String(year), effective_insurance_month: insuranceMonth, ...(paymentMonth ? {official_remittance_month: paymentMonth} : {})}}});
  };
  if (scope.insurer === 'kyokai') {
    verifyAnnualIndex(documents.healthIndex.html, year, 'health');
    const common = {insurer: 'kyokai', insured_category: 'general'};
    add('health_insurance', 'health', parseHealth(documents.health.html, year).get(scope.prefecture!)!, '2026-03-01', '2026-04-01', {...common, prefecture: scope.prefecture!});
    add('nursing_insurance', 'care', parseGeneralRate(documents.care.html, year, 3), '2026-03-01', '2026-04-01', common);
    add('child_support', 'child', parseGeneralRate(documents.child.html, year, 4), '2026-04-01', '2026-05-01', common);
  } else warnings.push('健康保険・介護保険・子ども子育て支援金は加入保険者の資料で確認してください。協会けんぽの値は取得していません。');
  add('pension_insurance', 'pension', parsePension(documents.pension.html), '2017-09-01', '2017-10-01', {scheme: 'employees_pension'});
  add('employment_insurance', 'employment', employment.total, '2026-04-01', null, {employment_business: scope.employment_business!, fiscal_year: '2026', effective_until: '2027-03-31'}, employment.employee, employment.employer);
  return {rates, checkedAt: now.toISOString(), year, warnings};
}
