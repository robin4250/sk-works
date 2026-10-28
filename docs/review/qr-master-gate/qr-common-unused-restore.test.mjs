// Isolated fixtures only. Native PostgreSQL in CI; PGlite may be injected locally.
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
const dir=dirname(fileURLToPath(import.meta.url));
const expand=p=>readFileSync(p,'utf8').split('\n').filter(l=>!l.startsWith('\\set')).map(l=>l.startsWith('\\ir ')?expand(resolve(dirname(p),l.slice(4))):l).join('\n');
const before=readFileSync(resolve(dir,'qr-common-public-contract-test.sql'),'utf8').split('\\ir qr-common-public-contract.sql.review-only')[0];
const fixture=before.split('\n').filter(l=>!l.startsWith('\\set')).map(l=>l.startsWith('\\ir ')?expand(resolve(dir,l.slice(4))):l).join('\n');
const apply=readFileSync(resolve(dir,'qr-common-public-contract.sql.review-only'),'utf8');
const restore=readFileSync(resolve(dir,'qr-common-public-contract-unused-restore.sql.review-only'),'utf8');
const restoreHashes=`do $$ declare r record; begin
 for r in select * from qr_attendance_private.public_contract_restore_functions loop
 perform set_config('sko.restore.qr_'||md5(r.signature),r.installed_md5,false);
 perform set_config('sko.review.qr_'||md5(r.signature),r.original_md5,false); end loop;
 perform set_config('sko.restore.qr_check_md5',(select installed_md5 from qr_attendance_private.public_contract_restore_check),false);
 perform set_config('sko.review.qr_check_md5',(select original_md5 from qr_attendance_private.public_contract_restore_check),false);
end $$;`;
const local=process.env.QR_TEST_PGLITE;
const session="select set_config('fixture.actor','00000000-0000-0000-0000-000000000001',false);select set_config('fixture.session','live',false);";
const cases=[
 ['unused exact restoration',null],
 ['enabled rollout',"update qr_attendance_private.public_contract_rollout set enabled=true"],
 ['saved QR setting',"insert into private.master_feature_settings(feature_key,enabled) values('qr_attendance',false)"],
 ['QR audit evidence',"insert into private.master_admin_audit_log(details) values('{\"feature_key\":\"qr_attendance\"}')"],
 ['function catalog drift',"alter function public.current_master_feature_flags() stable"],
 ['tampered original backup',"update qr_attendance_private.public_contract_restore_functions set original_definition=original_definition||' -- altered' where signature='public.current_master_feature_flags()'"],
 ['unexpected snapshot dependency',"create view private.unexpected_qr_dependency as select public.current_master_feature_flags_before_qr_candidate()"]
];
for(const [name,mutation] of cases){
 let db,dbName,execute,close;
 if(local){const {PGlite}=await import(local);db=new PGlite();execute=sql=>db.exec(session+sql);close=()=>db.close();}
 else {dbName='qr_restore_'+randomBytes(6).toString('hex');execFileSync('createdb',[dbName],{stdio:'pipe'});
 execute=async sql=>execFileSync('psql',['-X','-v','ON_ERROR_STOP=1','-d',dbName],{input:session+sql,stdio:'pipe'});
 close=async()=>execFileSync('dropdb',[dbName],{stdio:'pipe'});}
 try {
 await execute(fixture+apply+restoreHashes);
 await execute(`select set_config('fixture.actor','00000000-0000-0000-0000-000000000001',false);select set_config('fixture.session','live',false);`);
 if(mutation)await execute(mutation);
 if(mutation){
 await assert.rejects(execute(restoreHashes+restore));
 if(local)await db.exec('rollback');
 await execute(`do $$ begin
 if to_regclass('qr_attendance_private.public_contract_rollout') is null or
  public.current_master_feature_flags()->>'qr_attendance_contract_version' is distinct from '1' then
 raise exception 'failed restore changed installed contract'; end if; end $$;`);
 } else {
 await execute(restoreHashes+restore);
 await execute(`do $$ begin
 if public.current_master_feature_flags() ? 'qr_attendance' or
  (select flags from private.flags_dependency_fixture) ? 'qr_attendance' or
  'public.current_master_feature_flags()'::regprocedure::oid is distinct from
   (select original_oid from private.reader_oid_fixture) or
  to_regclass('qr_attendance_private.public_contract_rollout') is not null or
  (select count(*) from private.master_feature_settings)<>1 or
  (select count(*) from private.master_admin_audit_log)<>0 or
  not has_function_privilege('authenticated','public.current_master_feature_flags()','EXECUTE') or
  has_function_privilege('anon','public.current_master_feature_flags()','EXECUTE') then
 raise exception 'restore mismatch'; end if;
 begin insert into private.master_feature_settings(feature_key,enabled) values('qr_attendance',false);
 raise exception 'old CHECK not restored'; exception when check_violation then null; end;
 end $$;`);
 }
 process.stdout.write('ok '+name+'\n');
 } finally {await close();}
}
