// Reuses the existing disposable two-mode fixture. No external DB or real files.
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
let script = await fs.readFile(new URL('./verify_qualification_admin_saved_photos.mjs', import.meta.url), 'utf8');
const readAnchor = "const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');";
if (script.split(readAnchor).length !== 2) throw new Error('fixture read anchor changed');
script = script.replace(readAnchor, `const read=p=>fs.readFile(${JSON.stringify(root)}+p,'utf8');`);
const marker = ' // Exact original source drift failed before candidate DDL, checked above.';
if (script.split(marker).length !== 2) throw new Error('fixture test anchor changed');
const check = `
 // Reproduce the pre-prepare gap: the UI saw front only, server now has back too.
 await owner();await db.exec("set test.active='true'");
 await db.query("insert into worker_qualifications(id,company_id,worker_id,qualification_master_id,attachment_path,attachment_back_path)values($1,$2,$3,$4,$5,$6)",[id(40),company,worker,master,front,back]);
 const baselineData=(request,expected,selected=[])=>({company_id:company,target_id:id(40),request_id:id(request),expected_photo_paths:expected,photo_slots:selected.map(existing_path=>({existing_path}))});
 await actor(admin);
 const staleAccepted=await rpc('prepare_admin_saved_photos',baselineData(41,[front]));
 assert.equal(staleAccepted.status,'draft','RED: old candidate accepts a stale viewed baseline');
 await rpc('cancel_photos',{id:id(41)});
 await owner();
 const metadataSql="select oid::text,proowner::text,proacl::text,prosecdef,proconfig from pg_proc where oid='private.admin_qualification_saved_photos(text,jsonb)'::regprocedure";
 const beforeMetadata=(await db.query(metadataSql)).rows;
 const beforeRows=(await db.query('select to_jsonb(q) v from worker_qualifications q order by id')).rows;
 const beforeStorage=(await db.query('select to_jsonb(o) v from storage.objects o order by name')).rows;
 const patch=await read('docs/candidates/qualification_admin_photo_baseline_20261021.sql.review-only');
 await db.exec(patch);
 assert.deepEqual((await db.query(metadataSql)).rows,beforeMetadata);
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q order by id')).rows,beforeRows);
 await actor(admin);
 for(const baseline of [undefined,null,{},[],[front],[back,front],[front,back,back],[front,back,'unknown']]){
  await assert.rejects(rpc('prepare_admin_saved_photos',baselineData(42,baseline)),e=>e.code==='40001');
 }
 await owner();assert.equal((await db.query('select count(*)::int n from private.qualification_submissions where id=$1',[id(42)])).rows[0].n,0);
 await actor(admin);
 const accepted=await rpc('prepare_admin_saved_photos',baselineData(43,[front,back],[front]));
 assert.deepEqual(accepted.photo_paths,[front]);
 await rpc('submit',{id:id(43)});await actor(reviewer);await rpc('approve',{id:id(43)});
 await owner();assert.equal((await db.query('select attachment_back_path from worker_qualifications where id=$1',[id(40)])).rows[0].attachment_back_path,null);
 await actor(admin);
 assert.equal((await rpc('prepare_admin_saved_photos',baselineData(43,[front,back],[front]))).status,'approved','exact request retry stays idempotent after a legitimate approval');
 await rpc('prepare_admin_saved_photos',baselineData(44,[front],[]));
 await rpc('submit',{id:id(44)});await actor(reviewer);await rpc('approve',{id:id(44)});
 await owner();
 const cleared=(await db.query('select attachment_path,attachment_back_path,attachment_extra_paths from worker_qualifications where id=$1',[id(40)])).rows;
 assert.deepEqual(cleared,[{attachment_path:null,attachment_back_path:null,attachment_extra_paths:[]}]);
 assert.deepEqual((await db.query('select to_jsonb(o) v from storage.objects o order by name')).rows,beforeStorage);
 await assert.rejects(db.query('delete from worker_qualifications where id=$1',[id(40)]),e=>e.code==='42501');
 await assert.rejects(db.exec(patch),e=>e.code==='55000');await db.exec('rollback');
 console.log('PASS saved-photo prepare baseline: stale selection RED/fix, malformed/order/replaced baseline rejection before INSERT, matched removal/approval, replay, row and Storage retention, metadata preservation, unknown source refusal');
`;
script = script.replace(marker, check + '\n' + marker);
await import('data:text/javascript;base64,' + Buffer.from(script).toString('base64'));
