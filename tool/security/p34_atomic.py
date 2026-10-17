"""Review-only deterministic composition. Prints SQL; never connects or deploys."""
from pathlib import Path
import hashlib
import sys

SOURCES = {
 "20261016104441_personnel_direct_read_permission_guard.sql": "0b7c79de6cdf8419412d533aac06749e2ea9aed98b2eb1949a3045eddb96b99a",
 "20261016113335_personnel_legacy_read_permission_guard.sql": "33070658ff9f7a009c6897b7c91c0dfc6f713af0ada1ea14fe0546249632acc4",
 "20261016120458_personnel_write_permission_guard.sql": "63a0ec28f5b8bafdf85d3d1900e152c69d1f1a13c5c2e210aefdc8b98c5ff036",
}
def compose(root):
    parts=[]
    for name, digest in SOURCES.items():
        data=(Path(root)/"supabase/migrations"/name).read_bytes()
        if hashlib.sha256(data).hexdigest()!=digest:
            raise ValueError("Reviewed source drift")
        text=data.decode("utf-8")
        # Fixed outer bytes only. No global replace/parser or transaction stripping.
        if not text.startswith("begin;\n") or not text.endswith("commit;\n"):
            raise ValueError("Reviewed transaction envelope drift")
        parts.append(text[len("begin;\n"):-len("commit;\n")])
    legacy=parts[1].split("AS $function$\n",1)[1].split("\n$function$",1)[0]
    write=parts[2].split("as $$\n",1)[1].split("\n$$;",1)[0]
    checks=[]
    for signature,body in [("private.employee_personnel_rows()",legacy),("private.can_edit_worker_personnel(uuid)",write)]:
        # prosrc includes the delimiter-adjacent newline on both sides.
        expected=hashlib.md5(("\n"+body+"\n").encode()).hexdigest()
        checks.append("if (select md5(prosrc) from pg_proc where oid='"+signature+"'::regprocedure) is distinct from '"+expected+"' then raise exception 'Output source drift';end if;")
    pre="""begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
select pg_advisory_xact_lock(hashtextextended('sko.p34.atomic',0));
create temporary table p34_metadata on commit drop as
select p.oid,p.proowner,p.proacl,p.proconfig,p.prosecdef
from pg_proc p where p.oid in
('private.employee_personnel_rows()'::regprocedure,'private.can_edit_worker_personnel(uuid)'::regprocedure);
"""
    post="""do $p34$ begin
if (select count(*) from p34_metadata)<>2 or exists(
select 1 from p34_metadata s left join pg_proc p on p.oid=s.oid
where p.oid is null or p.proowner<>s.proowner or p.proacl is distinct from s.proacl
or p.proconfig is distinct from s.proconfig or p.prosecdef<>s.prosecdef)
then raise exception 'Output metadata drift';end if;
"""+ "\n".join(checks)+"""
if (select count(*) from pg_policies where schemaname='public'
and tablename in ('worker_personnel_profiles','worker_family_members')
and cmd='SELECT' and permissive='PERMISSIVE' and roles=array['authenticated']::name[])<>2
then raise exception 'Output policy contract drift';end if;
end $p34$;
commit;
"""
    return pre+"\n".join(parts)+post

if __name__=="__main__":
    if len(sys.argv)!=2: raise SystemExit("Usage: p34_atomic.py SOURCE_ROOT (prints review-only SQL)")
    print(compose(sys.argv[1]),end="")
