import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {fileURLToPath,pathToFileURL} from 'node:url';import {createHash,createHmac,randomUUID} from 'node:crypto';import {r20Setup,r20Verify,r20Http,r20Restore} from './r20_fixture.mjs';
const source27=[
  {
    "nspname": "private",
    "proname": "create_line_history_analysis",
    "args": "p_name text, p_command_id uuid",
    "body_hash": "a2b8073b520abf133e6ce958e5f8c7f6",
    "definition": "CREATE OR REPLACE FUNCTION private.create_line_history_analysis(p_name text, p_command_id uuid)\n RETURNS uuid\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO ''\nAS $function$\ndeclare cid uuid; gid uuid;\nbegin\n if auth.uid() is null or not private.line_client_access_allowed() or not public.is_current_user_master_admin() then raise exception 'master LINE access required' using errcode='42501'; end if;\n if p_command_id is null or nullif(btrim(p_name),'') is null or length(p_name)>200 then raise exception 'invalid analysis request' using errcode='22023'; end if;\n if (select count(*) from public.company_members where user_id=auth.uid())<>1 then raise exception 'company selection unavailable' using errcode='42501'; end if;\n select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin','manager');\n if cid is null or not private.has_company_feature(cid,'can_manage_invoices') then raise exception 'invoice management required' using errcode='42501'; end if;\n perform pg_advisory_xact_lock(hashtextextended('line-analysis:'||auth.uid()::text||p_command_id::text,0));\n select group_id into gid from private.line_history_analysis_groups where created_by=auth.uid() and command_id=p_command_id;\n if gid is not null then return gid; end if;\n gid:=private.create_custom_chat_group('過去履歴分析：'||left(btrim(p_name),190));\n insert into private.line_history_analysis_groups(group_id,company_id,command_id,created_by) values(gid,cid,p_command_id,auth.uid());\n return gid;\nend $function$\n",
    "owner": "postgres",
    "acl": "{postgres=X/postgres,authenticated=X/postgres}",
    "config": "{\"search_path=\\\"\\\"\"}",
    "prosecdef": true
  },
  {
    "nspname": "private",
    "proname": "create_custom_chat_group",
    "args": "p_name text",
    "body_hash": "ab890a5257750f8850297016bb4ec712",
    "definition": "CREATE OR REPLACE FUNCTION private.create_custom_chat_group(p_name text)\n RETURNS uuid\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO ''\nAS $function$\ndeclare\n  v_user uuid := auth.uid();\n  v_company uuid;\n  v_group uuid;\n  v_name text := btrim(coalesce(p_name,''));\nbegin\n  if v_user is null then raise exception 'ログインが必要です'; end if;\n  if v_name = '' then raise exception 'グループ名を入力してください'; end if;\n\n  select cm.company_id into v_company\n  from public.company_members cm\n  where cm.user_id = v_user\n  limit 1;\n  if v_company is null then raise exception '会社情報が見つかりません'; end if;\n\n  insert into public.communication_groups (\n    company_id,name,group_type,participants_only,created_by,last_activity_at\n  ) values (\n    v_company,v_name,'company',true,v_user,now()\n  )\n  returning id into v_group;\n\n  insert into public.communication_group_members(group_id,company_id,user_id)\n  values (v_group,v_company,v_user)\n  on conflict do nothing;\n\n  return v_group;\nend\n$function$\n",
    "owner": "postgres",
    "acl": null,
    "config": "{\"search_path=\\\"\\\"\"}",
    "prosecdef": true
  },
  {
    "nspname": "private",
    "proname": "guard_standard_company_chat",
    "args": "",
    "body_hash": "001d3b5791745e1093f0a1ba9339add6",
    "definition": "CREATE OR REPLACE FUNCTION private.guard_standard_company_chat()\n RETURNS trigger\n LANGUAGE plpgsql\n SET search_path TO ''\nAS $function$\nbegin\n if TG_OP='DELETE' then\n  -- Allow the parent company's own deletion flow to cascade, never standalone room removal.\n  if old.is_company_open_chat and exists(select 1 from public.companies where id=old.company_id) then\n   raise exception '会社オープンチャットは削除できません';\n  end if;\n  return old;\n end if;\n if new.is_company_open_chat is distinct from old.is_company_open_chat or\n    (old.is_company_open_chat and (new.company_id is distinct from old.company_id or\n     new.group_type is distinct from old.group_type or new.participants_only or\n     new.site_id is not null or new.name is distinct from old.name)) then\n  raise exception '会社オープンチャットの名前・参加範囲は変更できません';\n end if;\n return new;\nend $function$\n",
    "owner": "postgres",
    "acl": "{postgres=X/postgres}",
    "config": "{\"search_path=\\\"\\\"\"}",
    "prosecdef": false
  },
  {
    "nspname": "private",
    "proname": "keep_chat_visibility",
    "args": "",
    "body_hash": "8f67a9138508c4c42983da435b58c802",
    "definition": "CREATE OR REPLACE FUNCTION private.keep_chat_visibility()\n RETURNS trigger\n LANGUAGE plpgsql\n SET search_path TO ''\nAS $function$ begin\n if old.participants_only is distinct from new.participants_only then raise exception 'トークの公開範囲は変更できません'; end if;\n return new;\nend $function$\n",
    "owner": "postgres",
    "acl": "{postgres=X/postgres}",
    "config": "{\"search_path=\\\"\\\"\"}",
    "prosecdef": false
  },
  {
    "nspname": "private",
    "proname": "record_chat_creator",
    "args": "",
    "body_hash": "6f08a25cfe2db1947ee3dd79250526ac",
    "definition": "CREATE OR REPLACE FUNCTION private.record_chat_creator()\n RETURNS trigger\n LANGUAGE plpgsql\n SET search_path TO ''\nAS $function$\nbegin\n if TG_OP='INSERT' then new.created_by:=auth.uid(); else new.created_by:=old.created_by;end if;\n return new;\nend $function$\n",
    "owner": "postgres",
    "acl": "{postgres=X/postgres}",
    "config": "{\"search_path=\\\"\\\"\"}",
    "prosecdef": false
  }
];
let checks27=0;
async function groupPolicy27(db,actual){await db.exec('drop policy ordinary_scope on public.communication_groups');if(actual)await db.exec('drop policy fixture_ordinary_write on public.communication_groups');await db.exec(`create policy ordinary_scope on public.communication_groups for select to authenticated using(${actual?'private.can_access_communication_group(id)':'private.r19_scope(company_id)'})`);if(!actual)await db.exec('create policy fixture_ordinary_write on public.communication_groups for all to authenticated using(private.r19_scope(company_id)) with check(private.r19_scope(company_id))');}
async function r27Setup(db,id){
 await db.exec(`alter table private.line_history_analysis_groups add command_id uuid,add created_by uuid;
 create function private.line_client_access_allowed() returns boolean language sql as $$select true$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select private.r19_master()$$;
 create table private.r27_observations(group_id uuid,general_visible boolean,other_master_visible boolean,creator_visible boolean,lineage_exists boolean);`);
 for(const row of source27){assert.equal(createHash('md5').update(row.definition.split('$function$')[1]).digest('hex'),row.body_hash);await db.exec(row.definition);}
 for(const [name,when]of [['guard_standard_company_chat','BEFORE DELETE OR UPDATE'],['keep_chat_visibility','BEFORE UPDATE'],['record_chat_creator','BEFORE INSERT OR UPDATE']])await db.exec(`create trigger ${name} ${when} on public.communication_groups for each row execute function private.${name}()`);
 await db.exec(`create function private.r27_observe() returns trigger language plpgsql security definer set search_path='' as $$declare claims text;a boolean;b boolean;c boolean;begin if new.group_id in('${id(20)}','${id(31)}','${id(22)}')then return null;end if;claims:=current_setting('request.jwt.claims',true);perform set_config('request.jwt.claims','{"sub":"${id(2)}"}',true);a:=private.can_access_communication_group(new.group_id);perform set_config('request.jwt.claims','{"sub":"${id(6)}"}',true);b:=private.can_access_communication_group(new.group_id);perform set_config('request.jwt.claims',claims,true);c:=private.can_access_communication_group(new.group_id);insert into private.r27_observations values(new.group_id,a,b,c,exists(select 1 from private.line_history_analysis_groups where group_id=new.group_id));return null;end$$;create trigger r27_observe after insert on public.communication_group_members for each row execute function private.r27_observe();`);
}
async function verifyGroup27(db,id,gid){
 assert.deepEqual((await db.query('select general_visible,other_master_visible,creator_visible,lineage_exists from private.r27_observations where group_id=$1',[gid])).rows,[{general_visible:false,other_master_visible:false,creator_visible:true,lineage_exists:false}]);checks27++;
 assert.deepEqual((await db.query('select user_id from public.communication_group_members where group_id=$1',[gid])).rows,[{user_id:id(1)}]);checks27++;
 for(const actor of [id(2),id(6)]){assert.equal((await actor23(db,actor,()=>db.query('select id from public.communication_groups where id=$1',[gid]))).rows.length,0);checks27++;}
 assert.equal((await actor23(db,id(1),()=>db.query('select id from public.communication_groups where id=$1',[gid]))).rows.length,1);checks27++;
 assert.equal((await db.query('select count(*)::int n from public.chat_messages where communication_group_id=$1',[gid])).rows[0].n,0);checks27++;
 assert.equal((await db.query('select count(*)::int n from public.app_notifications where action_id=$1',[gid])).rows[0].n,0);checks27++;
}
async function r27Verify(db,id){
 await r27Setup(db,id);
 await db.exec('begin');try{await groupPolicy27(db,true);
 const call=()=>actor23(db,id(1),()=>db.query('select private.create_line_history_analysis($1,$2) gid',['synthetic',id(97)]));const first=await call();const gid=first.rows[0].gid;await verifyGroup27(db,id,gid);assert.deepEqual(await call(),first);checks27++;
 const ordinary=await actor23(db,id(2),()=>db.query('select private.create_custom_chat_group($1) gid',['ordinary fixture']));assert.equal((await actor23(db,id(2),()=>db.query('select private.can_access_communication_group($1) b',[ordinary.rows[0].gid]))).rows[0].b,true);checks27++;
 }finally{await db.exec('rollback');}
 await actor23(db,id(2),()=>assert.rejects(db.query('select private.create_line_history_analysis($1,$2)',['synthetic',id(98)]),e=>e.code==='42501'));checks27++;
}
async function r27Http(db,id,token,origin){
 await db.exec(`create function public.r27_create(p_command uuid) returns uuid language sql security invoker set search_path='' as $$select private.create_line_history_analysis('synthetic',p_command)$$;revoke all on function public.r27_create(uuid) from public,anon;grant execute on function public.r27_create(uuid) to authenticated;notify pgrst,'reload schema';`);
 const invoke=(actor,command)=>fetch(new URL('/rpc/r27_create',origin),{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'},body:JSON.stringify({p_command:command})});let ready=false;for(let i=0;i<30;i++){const r=await invoke(id(2),randomUUID());if(r.status===403){ready=true;break;}assert.ok([404,503].includes(r.status));await new Promise(r=>setTimeout(r,100));}assert.ok(ready);
 const command=randomUUID();let gid;await groupPolicy27(db,true);
 try{const denied=await invoke(id(2),command);assert.equal(denied.status,403);checks27++;const first=await invoke(id(1),command);assert.equal(first.status,200);gid=await first.json();await verifyGroup27(db,id,gid);const repeat=await invoke(id(1),command);assert.equal(repeat.status,200);assert.equal(await repeat.json(),gid);checks27++;
 for(const actor of [id(2),id(6)]){const r=await fetch(new URL('/communication_groups?id=eq.'+gid,origin),{headers:{Authorization:'Bearer '+token(actor)},redirect:'error'});assert.equal(r.status,200);assert.deepEqual(await r.json(),[]);checks27++;}
 }finally{if(gid){await db.query('delete from private.line_history_analysis_groups where group_id=$1',[gid]);await db.query('delete from public.communication_group_members where group_id=$1',[gid]);await db.query('delete from public.communication_groups where id=$1',[gid]);await db.query('delete from private.r27_observations where group_id=$1',[gid]);}await groupPolicy27(db,false);}
}
async function r27Restore(){console.log(`PASS ${checks27} R27 original analysis group creation visibility checks; no product patch was needed for this tested ordering path.`);}
const levels27=[['r26','const levels26='],['r25','const source25='],['r24','const source24='],['r23','const source23='],['r22','const source22='],['r21',"if(fileURLToPath(import.meta.url)===process.argv[1])"]];const self27=await fs.readFile(fileURLToPath(import.meta.url),'utf8');let adapted27=self27.slice(0,self27.indexOf('const levels27='));for(const [name,marker]of levels27){const s=await fs.readFile(new URL('./'+name+'_fixture.mjs',import.meta.url),'utf8');adapted27+='\n'+s.slice(0,s.indexOf(marker)).replace(/^import .*;\n/gm,'');}const source19=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');adapted27+='\n'+source19.replace(/^import .*;\n/gm,'');
for(const [anchor,replacement]of [
 ['  const before=await Promise.all','  await r21Setup(db,id);await r22Setup(db,id);await r23Setup(db,id);await r24Setup(db);await r26Setup(db,id);await db.exec("alter table public.invoices alter id set default gen_random_uuid(),add subtotal numeric,add welfare_amount numeric,add adjustments numeric,add detail_mode text,add automatic_calculation boolean;alter table public.communication_groups alter id set default gen_random_uuid(),add last_activity_at timestamptz,add is_company_open_chat boolean default false,add site_id uuid");\n  const before=await Promise.all'],
 ['  const helpers=(await db.query','  await r21Verify(db,id);await r22Verify(db,id);await r23Verify(db,id);await r24Verify(db,id);await r25Verify(db,id);await r26Verify(db,id);await r27Verify(db,id);\n  const helpers=(await db.query'],
 ["    console.log('VERIFIED actual PG17","    await r21Http(db,id,token,origin);await r22Http(db,id,token,origin);await r23Http(db,id,token,origin);await r24Http(db,id,token,origin);await r25Http(db,id,token,origin);await r26Http(db,id,token,origin);await r27Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
 ['  for(let i=0;i<tables.length;i++){','  await r27Restore();await r26Restore(db);await r25Restore(db);await r24Restore(db);await r23Restore(db);await r22Restore(db);await r21Restore(db);\n  for(let i=0;i<tables.length;i++){']
 ]){assert.equal(adapted27.split(anchor).length,2);adapted27=adapted27.replace(anchor,replacement);}
const temp27=new URL(`./.r27-${randomUUID()}.mjs`,import.meta.url);try{await fs.writeFile(temp27,adapted27,{mode:0o600,flag:'wx'});await import(temp27.href);}finally{await fs.unlink(temp27).catch(()=>{});}
