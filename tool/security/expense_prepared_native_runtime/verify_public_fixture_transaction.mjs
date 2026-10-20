import assert from'node:assert/strict';
const{PGlite}=await import(process.argv[2]);const db=new PGlite();
try{
 await db.exec(`CREATE ROLE sko_expense_bootstrap SUPERUSER LOGIN;CREATE ROLE sko_expense_installer LOGIN;ALTER SCHEMA public OWNER TO sko_expense_bootstrap;REVOKE ALL ON SCHEMA public FROM PUBLIC,sko_expense_installer;GRANT USAGE ON SCHEMA public TO sko_expense_installer;SET SESSION AUTHORIZATION sko_expense_bootstrap;`);
 const snapshot=async()=>(await db.query(`SELECT jsonb_build_object('owner',nspowner,'acl',nspacl) AS value FROM pg_namespace WHERE nspname='public'`)).rows[0].value;
 const before=await snapshot();
 assert.equal((await db.query(`SELECT has_schema_privilege('sko_expense_installer','public','CREATE') value`)).rows[0].value,false);
 await db.exec(`BEGIN;GRANT CREATE ON SCHEMA public TO sko_expense_installer;SET LOCAL ROLE sko_expense_installer;CREATE FUNCTION public.sko_expense_fixture_only() RETURNS boolean LANGUAGE sql AS $$SELECT true$$;RESET ROLE;`);
 assert.equal((await db.query('SELECT current_user AS value')).rows[0].value,'sko_expense_bootstrap');
 await db.exec(`REVOKE CREATE ON SCHEMA public FROM sko_expense_installer;COMMIT;`);
 assert.deepEqual(await snapshot(),before);
 assert.equal((await db.query(`SELECT pg_get_userbyid(proowner) AS value FROM pg_proc WHERE oid='public.sko_expense_fixture_only()'::regprocedure`)).rows[0].value,'sko_expense_installer');
 assert.equal((await db.query(`SELECT has_schema_privilege('sko_expense_installer','public','CREATE') value`)).rows[0].value,false);
 await db.exec(`BEGIN;SET LOCAL ROLE sko_expense_installer;DROP FUNCTION public.sko_expense_fixture_only();COMMIT;`);
 assert.deepEqual(await snapshot(),before);
 console.log('PASS PostgreSQL17 mapped installer: transaction grant/create/reset/revoke/COMMIT and separate owner undo preserve original public owner/ACL; native proof=false');
}finally{await db.close();}
