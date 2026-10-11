begin;
set local lock_timeout = '5s';
-- One requirement and submission serves both destinations. Keep all saved data.
alter table public.document_requirements drop constraint document_requirements_scope_check;
alter table public.document_requirements add constraint document_requirements_scope_check
 check (scope in ('internal', 'upstream', 'both'));
alter table public.document_requirements drop constraint document_requirement_upstream_scope;
alter table public.document_requirements add constraint document_requirement_upstream_scope
 check ((scope in ('upstream', 'both') or upstream_name = '')
 and upstream_name = btrim(upstream_name) and char_length(upstream_name) <= 200);
-- Preserve exchange access checks, retry behavior and immutable snapshots.
do $shared$
declare definition text;
begin
 definition := pg_get_functiondef('private.company_document_exchange(text,jsonb)'::regprocedure);
 if md5(definition) <> 'a96cab4fde9983c3d0f26f2c7f0094e7'
 or (length(definition)-length(replace(definition, 'dr.scope=''upstream''', '')))
 / length('dr.scope=''upstream''') <> 3 then
 raise exception 'Document exchange changed; inspect before shared-scope deployment' using errcode='55000';
 end if;
 execute replace(definition, 'dr.scope=''upstream''', 'dr.scope in (''upstream'',''both'')');
end $shared$;
commit;
