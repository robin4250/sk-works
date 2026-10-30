import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const dependency = process.env.SKO_PGLITE_MODULE || resolve('tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js');
const { PGlite } = await import(pathToFileURL(dependency));
const db = new PGlite();
const schema = readFileSync('docs/review/site-order-management/archive-schema.sql.review-only','utf8');
let checks=0;
const assert = (ok,message) => { if(!ok)throw new Error(message); checks++; };
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
async function denied(sql, code) {
  await db.exec('savepoint deny_check');
  let error;
  try { await db.exec(sql); } catch(e) { error=e; }
  await db.exec('rollback to savepoint deny_check; release savepoint deny_check');
  assert(error && (!code || error.code===code),`expected ${code}: ${sql}; got ${error?.code}`);
}
function artifact(n,company,site,kind='order') { return `insert into site_order_private.artifacts
 (id,revision,company_id,source_site_id,kind,work_name,starts_on,ends_on,pdf_sha256,
 pdf_byte_length,pdf_storage_path,trusted_issuer_receipt_id,company_snapshot,
 seal_version_id,canonical_price_lines,created_by) values
 ('${id(n)}',1,'${id(company)}','${id(site)}','${kind}','工事名称','2026-10-01','2026-10-31',
 '${'a'.repeat(64)}',1024,'private/${id(n)}','${id(n+1000)}','{}','${id(n+2000)}',
 '[{"item":"とび工","unit_price_yen":32000,"unit":"人日"}]','${id(100)}')`; }
try {
  await db.exec('create role anon; create role authenticated; alter default privileges grant all on tables to authenticated');
  await db.exec(schema.replace(/rollback;\s*$/i,''));
  await db.exec(artifact(10,1,101));
  await db.exec(artifact(11,2,102,'acceptance'));
  const delivery = `insert into site_order_private.deliveries
    (id,sender_company_id,recipient_company_id,registered_trade_company_id,connection_version,
    request_id,source_site_id,site_share_data_item_id,artifact_id,artifact_revision,sent_by,sent_session_id)
    values('${id(20)}','${id(1)}','${id(2)}','${id(30)}',1,'${id(40)}','${id(101)}',
    '${id(50)}','${id(10)}',1,'${id(100)}','${id(200)}')`;
  await db.exec(delivery);
  const notice=(n,kind,audience)=>`insert into site_order_private.notification_outbox
    (id,delivery_id,original_sender_company_id,original_recipient_company_id,audience_company_id,event_kind)
    values('${id(n)}','${id(20)}','${id(1)}','${id(2)}','${id(audience)}','${kind}')`;
  await db.exec(notice(70,'approval_required',2));
  await denied(notice(71,'approval_required',1),'23514');
  await denied(notice(71,'approval_required',2),'23505');
  await denied(notice(72,'order_accepted',1),'23503');
  await denied(delivery.replace(id(20),id(21)).replace(id(50),id(51))
    .replace(id(40),id(41)).replace(id(101),id(999)),'23503');
  await denied(delivery.replace(id(20),id(21)).replace(id(50),id(51)),'23505');
  await denied(delivery.replace(id(20),id(21)).replace(id(40),id(41))
    .replace(id(50),id(51)).replace(id(10),id(11)),'23503');
  const outbox = `insert into site_order_private.acceptance_outbox
    (id,approval_delivery_id,sender_company_id,recipient_company_id,artifact_id,artifact_revision,source_site_id)
    values('${id(60)}','${id(20)}','${id(2)}','${id(1)}','${id(11)}',1,'${id(102)}')`;
  await denied(outbox.replace(id(1),id(3)),'23503');
  await denied(outbox.replace(id(11),id(10)),'23503');
  const response = `insert into site_order_private.responses
    (delivery_id,recipient_company_id,decision,accepted_site_id,acceptance_outbox_id,
    responded_by,responded_session_id) values ('${id(20)}','${id(2)}','accepted',
    '${id(102)}','${id(60)}','${id(101)}','${id(201)}')`;
  await denied(response.replace(`'${id(60)}'`,'null'),'23514');
  await denied(response,'23503');
  await db.exec(outbox);
  await denied('set constraints all immediate','23503');
  await denied(response.replace(id(102),id(103)),'23503');
  await db.exec(response);
  await db.exec('set constraints all immediate');
  await db.exec(notice(72,'order_accepted',1));
  await db.exec(notice(73,'acceptance_delivery_pending',2));
  await denied(notice(74,'acceptance_received',2),'23514');
  await denied(notice(75,'order_rejected',1),'23503');
  assert((await db.query('select count(*)::int n from site_order_private.responses')).rows[0].n===1,
    'approval and exact original-sender acceptance intent committed together');
  for(const table of ['artifacts','deliveries','responses','acceptance_outbox','notification_outbox']) {
    await denied(`delete from site_order_private.${table}`,'55000');
    await denied(`update site_order_private.${table} set created_at=now()`
      .replace('responses set created_at','responses set responded_at')
      .replace('deliveries set created_at','deliveries set sent_at'),'55000');
  }
  const tables=(await db.query(`select relname,relrowsecurity from pg_class c
    join pg_namespace n on n.oid=c.relnamespace where n.nspname='site_order_private' and relkind='r'`)).rows;
  assert(tables.length===5 && tables.every(t=>t.relrowsecurity),'all archive tables RLS');
  const privileges=(await db.query(`select has_table_privilege('authenticated',
    'site_order_private.artifacts','insert') client_insert,
    has_schema_privilege('authenticated','site_order_private','usage') schema_usage`)).rows[0];
  assert(!privileges.client_insert && !privileges.schema_usage,'explicit revoke survives global default grants');
  const api=(await db.query(`select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like '%site_order%'`)).rows[0].n;
  assert(api===0,'foundation exposes no incomplete production RPC');
  await db.exec('create role site_order_fixture_client; grant usage on schema site_order_private to site_order_fixture_client; set local role site_order_fixture_client');
  await denied('select * from site_order_private.artifacts','42501');
  await db.exec('reset role');
  await db.exec('rollback');
  console.log(JSON.stringify({status:'passed',checks,scope:'offline structural prototype; no RPC/auth/issuer/real delivery proof',production_applied:false}));
} finally { await db.close(); }
