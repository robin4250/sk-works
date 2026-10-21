// Disposable fixture; actual existing attachment SQL and official registered-seal SQL.
import fs from 'node:fs/promises';import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';import {deflateSync} from 'node:zlib';
let db;
if(process.argv[3]==='postgres'){
 const pg=(await import(process.argv[2])).default;const url=new URL(process.env.SKO_CONSENT_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_document_consent_fixture')throw Error('disposable loopback consent fixture required');
 const client=new pg.Client({connectionString:url.href});await client.connect();
 db={query:(...a)=>client.query(...a),exec:s=>client.query(s),close:()=>client.end()};
}else{const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function crc32(bytes){let c=0xffffffff;for(const b of bytes){c^=b;for(let k=0;k<8;k++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type);const size=Buffer.alloc(4);size.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([size,t,data,crc]);}
function png(color){const h=Buffer.alloc(13);h.writeUInt32BE(32,0);h.writeUInt32BE(32,4);h[8]=8;h[9]=6;const raw=Buffer.alloc(32*(1+32*4));for(let y=0;y<32;y++)for(let x=0;x<32;x++){const n=y*129+1+x*4;raw[n]=color;raw[n+3]=x%2?255:0;}return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',h),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}

const A=id(1),B=id(2),C=id(3),UA=id(11),UB=id(12),UV=id(13),UC=id(14),PC=id(21),INV=id(22),PARTNER=id(23),CUSTOMER=id(24);
let request=1000,n=0;
const actor=async uid=>{await db.exec('reset role');await db.query("select set_config('test.uid',$1,false)",[uid]);};
const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0]?.v;
const check=(a,b)=>{assert.deepEqual(a,b);n++;};
const deny=async(fn,pattern)=>{await assert.rejects(fn,pattern);n++;};
const standalone=(amount=100)=>({kind:'order',issuer_company_id:A,counterparty_company_id:B,
 issuer:{name:'甲会社'},counterparty:{name:'乙会社'},total_amount_yen:amount,work_name:'合成工事'});
const prepare=(doc,expected=0,body=standalone())=>q('select trade_document_consent_private.prepare_document($1,$2,$3,$4,$5::jsonb) v',[doc,A,B,expected,JSON.stringify({...body,transaction_id:doc})]);
const localId=(doc,cid)=>id(10000+Number(doc.slice(-12))*10+Number(cid.slice(-12)));
const preview=async(doc,rev,cid)=>{await db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[doc,cid,localId(doc,cid)]);return q('select trade_document_consent_private.preview_own($1,$2,$3) v',[doc,rev,cid]);};
const decide=(doc,rev,cid,p,action='approve',rid=id(++request),hash=p.own_seal.seal_hash,confirmed=true)=>q('select trade_document_consent_private.decide($1,$2,$3,$4,$5,$6,$7,$8,$9) v',[doc,rev,cid,p.epoch,p.body_hash,action,hash,confirmed,rid]);
const render=(doc,rev,cid,archive=false)=>q('select trade_document_consent_private.render_approved($1,$2,$3,$4) v',[doc,rev,cid,archive]);
const upload=async(cid,name,rev,color)=>{const bytes=png(color);return q('select public.save_company_uploaded_seal($1,$2,$3,$4,$5,true) v',[cid,name,rev,bytes.toString('base64'),createHash('sha256').update(bytes).digest('hex')]);};
try{
await db.exec(`create role anon;create role authenticated;create role service_role;create schema private;create schema auth;
create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed()returns boolean language sql as $$select coalesce(current_setting('test.blocked',true),'false')<>'true'$$;
create table companies(id uuid primary key,name text,address text,corporate_number text,company_seal_enabled boolean,company_seal_style text);
create table company_members(company_id uuid,user_id uuid,role text);
create function private.has_company_feature(cid uuid,feature text)returns boolean language sql as $$
 select exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid()) and
 case feature when 'can_view_invoices' then coalesce(current_setting('test.invoice_view',true),'true')='true'
 when 'can_manage_invoices' then coalesce(current_setting('test.invoice_manage',true),'true')='true' else false end $$;
create table partner_companies(id uuid primary key,company_id uuid,name text,address text,president_name text);
create table customers(id uuid primary key,company_id uuid,name text,billing_name text,billing_address text);
create table payment_certificates(id uuid primary key,company_id uuid,partner_company_id uuid,period_start date,period_end date,revision int,status text,finalized_at timestamptz,gross_amount int,snapshot jsonb,calculation_blocked boolean default false);
create table invoices(id uuid primary key,company_id uuid,customer_id uuid,billing_period_start date,billing_period_end date,updated_at timestamptz,status text,finalized_at timestamptz,grand_total int,tax int,snapshot jsonb,calculation_blocked boolean default false,approval_finalized_at timestamptz,invoice_seal_frozen boolean default false);
create function private.document_company_seal_snapshot(jsonb,uuid,boolean)returns jsonb language sql as $$select jsonb_build_object('company_seal_snapshot',jsonb_build_object('version',1,'style','legacy','name',name))from public.companies where id=$2$$;
grant usage on schema private,auth to authenticated;`);
await db.exec(await fs.readFile(new URL('../supabase/migrations/20261014124714_monthly_trade_document_attachment.sql',import.meta.url),'utf8'));

 const design=await fs.readFile('supabase/migrations/20261010160154_company_seal_png_designs.sql','utf8');
 await db.exec(design.slice(design.indexOf('create or replace function private.document_company_seal_snapshot')));
 await db.exec("create function private.aoyagi_reisho_name_supported(text) returns boolean language sql as $$select true$$");
 await db.exec(await fs.readFile('docs/candidates/company_seal_uploaded_png_20261020.sql.review-only','utf8'));
 const connection=await fs.readFile('supabase/migrations/20261001213349_add_company_connection_foundation.sql','utf8');
 await db.exec(connection.slice(0,connection.indexOf('create or replace function private.company_connection_targets')));
 await db.query("insert into companies values($1,'甲会社','甲住所','1111111111111',true,'legacy'),($2,'乙会社','乙住所','2222222222222',true,'legacy'),($3,'無関係会社','丙住所','3333333333333',true,'legacy')",[A,B,C]);
 await db.query("insert into company_members values($1,$2,'owner'),($3,$4,'admin'),($1,$5,'viewer'),($6,$7,'admin')",[A,UA,B,UB,UV,C,UC]);
 await db.query("insert into private.company_connections(parent_company_id,child_company_id,status,requested_by) values($1,$2,'accepted',$3)",[A,B,UA]);
 await db.query("insert into partner_companies values($1,$2,'乙会社','乙住所','乙代表')",[PARTNER,A]);
 await db.query("insert into customers values($1,$2,'乙会社','乙会社','乙住所')",[CUSTOMER,A]);
 await db.query("insert into payment_certificates values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',null,110000,'{}',false)",[PC,A,PARTNER]);
 await db.query("insert into invoices values($1,$2,$3,'2026-10-01','2026-10-31','2026-10-14T12:00:00Z','draft',null,110000,10000,'{}',false,now(),false)",[INV,A,CUSTOMER]);
 await db.exec(await fs.readFile('docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only','utf8'));
 await actor(UA);
 const doc=id(31);await prepare(doc);
 let p=await preview(doc,1,A);check(p.own_seal.snapshot.style,'legacy');check(p.own_seal.version_key.startsWith('snapshot-v1:'),true);
 check(JSON.stringify(p).includes('乙会社'),false); // Own preview carries no other-party seal/body.
 await deny(()=>render(doc,1,A),/approved/);
 await deny(()=>decide(doc,1,A,p,'approve',id(++request),p.own_seal.seal_hash,false),/explicit/);
 const rid=id(++request),first=await decide(doc,1,A,p,'approve',rid);check(first.current_state,'open');
 check(await decide(doc,1,A,p,'approve',rid),first);
 await actor(UB);await upload(B,'乙会社',0,255);
 await deny(()=>preview(doc,1,A),/permission/);
 await preview(doc,1,B);
 await deny(()=>render(doc,1,B),/approved/);
 p=await preview(doc,1,B);check(p.own_seal.snapshot.style,'uploaded_png');
 await decide(doc,1,B,p);
 const approved=await render(doc,1,B);await actor(UA);check(await render(doc,1,A),approved);
 check(approved.seals.length,1);check(approved.consents.length,2);check(approved.seals.find(s=>s.company_id===A).seal_snapshot.style,'legacy');
 // Rotation after full approval preserves the exact saved document and seal metadata.
 await upload(A,'甲会社',0,128);check(await render(doc,1,A),approved);
 await db.query("update private.company_connections set status='disabled'");
 check(await render(doc,1,A,true),approved);
 await deny(()=>prepare(id(32)),/accepted/);
 await db.query("update private.company_connections set status='accepted'");
 await prepare(doc,1,standalone(101));
 await deny(()=>render(doc,1,A),/approved/);check(await render(doc,1,A,true),approved);
 await deny(()=>render(doc,2,A),/approved/);
 // Change/reapproval + stale epoch; no old consent is implicitly reused.
 let ap=await preview(doc,2,A);await actor(UB);const staleB=await preview(doc,2,B);
 await actor(UA);await decide(doc,2,A,ap);
 await actor(UB);await deny(()=>decide(doc,2,B,staleB),/revision/);
 await decide(doc,2,B,await preview(doc,2,B));check((await render(doc,2,B)).body.total_amount_yen,101);
 // Pending A consent cannot newly use a rotated seal to complete B's approval.
 const rotating=id(33);await actor(UA);await prepare(rotating);
 await decide(rotating,1,A,await preview(rotating,1,A));
 await upload(A,'甲会社',1,64);
 await actor(UB);await deny(async()=>decide(rotating,1,B,await preview(rotating,1,B)),/reconfirm/);
 await actor(UA);await decide(rotating,1,A,await preview(rotating,1,A));
 await actor(UB);await decide(rotating,1,B,await preview(rotating,1,B));check((await render(rotating,1,B)).seals.length,1);
 // Local pages are distinct; reverse orders never collapse an unordered pair.
 check(localId(doc,A)===localId(doc,B),false);
 const reverse=id(39),reverseBody={kind:'order',transaction_id:reverse,issuer_company_id:B,counterparty_company_id:A,issuer:{name:'乙会社'},counterparty:{name:'甲会社'},total_amount_yen:100};
 await q('select trade_document_consent_private.prepare_document($1,$2,$3,0,$4::jsonb) v',[reverse,B,A,JSON.stringify(reverseBody)]);
 await decide(reverse,1,B,await preview(reverse,1,B));await actor(UA);await decide(reverse,1,A,await preview(reverse,1,A));
 const reverseRender=await render(reverse,1,A);check(reverseRender.render_seal_company_id,B);check(reverseRender.transaction_id===doc,false);
 await deny(()=>db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[reverse,A,localId(doc,A)]),/another directional/);
 // The corresponding acceptance is another document kind/issuer, not the order page.
 const acceptance=id(38),acceptanceBody={...reverseBody,kind:'acceptance',transaction_id:doc};await actor(UB);
 await q('select trade_document_consent_private.prepare_document($1,$2,$3,0,$4::jsonb) v',[acceptance,B,A,JSON.stringify(acceptanceBody)]);
 await decide(acceptance,1,B,await preview(acceptance,1,B));await actor(UA);await decide(acceptance,1,A,await preview(acceptance,1,A));
 check((await render(acceptance,1,A)).document_role,'accepting_company');check((await render(acceptance,1,A)).render_seal_company_id,B);
 // Distinct reject / return / cancel, no approval or raw seal leak from legacy approval.
 for(const [num,action,state] of [[34,'reject','rejected'],[35,'return','returned'],[36,'cancel','cancelled']]){
  await actor(UA);const target=id(num);await prepare(target);const before=await preview(target,1,A);
  check((await decide(target,1,A,before,action)).current_state,state);
  await deny(()=>render(target,1,A),/approved/);
 }
 await actor(UV);await deny(()=>preview(doc,2,A),/permission/);await actor(UC);await deny(()=>render(doc,2,C),/company-specific/);
 await actor(UA);await db.exec('set role authenticated');await deny(()=>db.query('select * from trade_document_consent_private.consents'),/permission denied/);await db.exec('reset role');
 // Parent path defaults fail closed until a real formal mapping adapter is connected.
 await deny(()=>q('select trade_document_consent_private.prepare_document($1,$2,$3,0,$4::jsonb,$5,$6,$7,1) v',[id(40),A,B,JSON.stringify({...standalone(),transaction_id:id(40)}),'invoice',INV,'2026-10-14 12:00:00+00']),/not connected/);
 await deny(()=>q('select trade_document_consent_private.confirm_local_document($1,$2,2,$3::jsonb,$4,true,true) v',[localId(doc,A),A,'{}',id(++request)]),/not connected/);
 // A READ ONLY disposable adapter binds the actual existing attachment SQL.
 // Its explicit fixture mapping is not a production company-resolution implementation.
 await db.exec("create table private.fixture_formal_counterparty(subject_kind text,subject_id uuid,peer_company_id uuid,primary key(subject_kind,subject_id))");
 await db.query("insert into private.fixture_formal_counterparty values('payment_certificate',$1,$2)",[PC,B]);
 const workspace=await q("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[PC]);
 const payload={...workspace.defaults,issue_date:'2026-10-15',work_name:'当月工事',work_address:'東京都',tax_amount_yen:10000,intro_text:'工事発注',payment_conditions:'翌月末',notes:'',issuer:{...workspace.defaults.issuer,representative_name:'甲代表'},counterparty:{...workspace.defaults.counterparty,corporate_number:'2222222222222'}};
 await q("select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2::jsonb) v",[PC,JSON.stringify(payload)]);
 await db.exec(`create or replace function trade_document_consent_private.parent_binding(kind text,parent_id uuid,own_company uuid,peer_company uuid) returns jsonb language plpgsql security definer set search_path='' as $$
 declare parent jsonb;att private.trade_document_attachments%rowtype;
 begin
 if kind<>'payment_certificate' or not exists(select 1 from private.fixture_formal_counterparty where subject_kind=kind and subject_id=parent_id and peer_company_id=peer_company) then raise exception 'exact formal mapping unavailable';end if;
 select to_jsonb(p) into parent from public.payment_certificates p where id=parent_id and company_id=own_company for share;
 select * into att from private.trade_document_attachments where subject_kind=kind and subject_id=parent_id and company_id=own_company for share;
 if parent is null or att.subject_id is null or att.source_revision is distinct from parent->>'revision' then raise exception 'parent or attachment changed';end if;
 return jsonb_build_object('parent_revision',parent->>'revision','parent_fingerprint',md5(parent::text),
 'attachment_version',att.version,'attachment_fingerprint',md5(att.payload::text),
 'attachment_payload',att.payload-array['company_seal_snapshot','company_seal_enabled'],
 'internal_confirmation',jsonb_build_object('financial_status',parent->'status','separate_from_other_company_seal_consent',true));
 end $$`);
 const linkedBody={...payload,issuer_company_id:A,counterparty_company_id:B,transaction_id:id(41)};delete linkedBody.company_seal_snapshot;delete linkedBody.company_seal_enabled;
 const linked=id(41),financialBefore=await q('select to_jsonb(p) v from payment_certificates p where id=$1',[PC]);
 await q("select trade_document_consent_private.prepare_document($1,$2,$3,0,$4::jsonb,'payment_certificate',$5,'1',1) v",[linked,A,B,JSON.stringify(linkedBody),PC]);
 await db.exec("create or replace function trade_document_consent_private.linked_view_allowed(kind text,parent_id uuid,doc uuid,rev int,cid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role in ('owner','admin'))$$");
 await decide(linked,1,A,await preview(linked,1,A));
 await actor(UB);await decide(linked,1,B,await preview(linked,1,B));const linkedApproved=await render(linked,1,B);
 check(await q('select to_jsonb(p) v from payment_certificates p where id=$1',[PC]),financialBefore);
 await db.query('update payment_certificates set revision=2 where id=$1',[PC]);
 await deny(()=>render(linked,1,B),/changed/);check(await render(linked,1,B,true),linkedApproved);
 // ACK receipt replay is historical metadata, never active rendering authorization after cancel.
 await actor(UA);const active=await q('select jsonb_build_object(\'epoch\',epoch,\'body_hash\',body_hash) v from trade_document_consent_private.revisions where document_id=$1 and revision=2',[doc]);
 const cancelPreview={...active,own_seal:{seal_hash:null}};
 await db.query("update private.company_connections set status='disabled'");
 await decide(doc,2,A,cancelPreview,'cancel');
 await deny(()=>render(doc,2,A),/approved/);
 await db.exec('set role anon');await deny(()=>db.query('select trade_document_consent_private.own_seal($1)',[B]),/permission denied/);await db.exec('reset role');
 check((await q('select count(*)::int v from payment_certificates')),1);
 check((await q('select count(*)::int v from invoices')),1);
 console.log('PASS '+n+' bound consent checks; official v1/v2 seal source, both-party identical render, changes/replay/rotation, denied leak/actor, independent IDs, actual attachment binding, no parent financial writes');
}finally{await db.close();}

