-- Only role catalog attributes, credential ABSENCE boolean and dependency counts.
-- No password/hash/token/actor/user/session data is selected.
select jsonb_build_object('schema',1,
 'role',(select to_jsonb(r)-'rolpassword' from pg_roles r where rolname='sko_security_collector_ingest'),
 'credential_absent',not exists(select 1 from pg_authid r where rolname='sko_security_collector_ingest' and rolpassword is not null),
 'memberships',(select count(*) from pg_auth_members where roleid=(select oid from pg_roles where rolname='sko_security_collector_ingest') or member=(select oid from pg_roles where rolname='sko_security_collector_ingest')),
 'dependencies',(select count(*) from pg_shdepend where refclassid='pg_authid'::regclass and refobjid=(select oid from pg_roles where rolname='sko_security_collector_ingest'))
) inventory;
