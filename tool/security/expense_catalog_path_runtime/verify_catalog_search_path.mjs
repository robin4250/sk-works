import assert from'node:assert/strict';
const{PGlite}=await import(process.argv[2]);const db=new PGlite();
const capture=`SELECT e.evtfoid::regprocedure::text AS display,n.nspname AS namespace,p.proname,p.pronargs=0 AS no_arguments,md5(p.prosrc) AS source_md5,p.proacl AS acl FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid JOIN pg_namespace n ON n.oid=p.pronamespace WHERE e.evtname='synthetic_expense_display'`;
try{
 await db.exec(`CREATE SCHEMA extensions;CREATE SCHEMA shadow;CREATE FUNCTION extensions.synthetic_display() RETURNS event_trigger LANGUAGE plpgsql AS $$BEGIN NULL;END$$;CREATE EVENT TRIGGER synthetic_expense_display ON ddl_command_end EXECUTE FUNCTION extensions.synthetic_display();SET search_path=public,extensions;`);
 const visible=(await db.query(capture)).rows[0];assert.equal(visible.display,'synthetic_display()');
 await db.exec('SET search_path=public;');const fixed=(await db.query(capture)).rows[0];assert.equal(fixed.display,'extensions.synthetic_display()');
 assert.deepEqual({...visible,display:fixed.display},fixed);
 await db.exec(`CREATE FUNCTION shadow.synthetic_display() RETURNS event_trigger LANGUAGE plpgsql AS $$BEGIN NULL;END$$;DROP EVENT TRIGGER synthetic_expense_display;CREATE EVENT TRIGGER synthetic_expense_display ON ddl_command_end EXECUTE FUNCTION shadow.synthetic_display();SET search_path=public,shadow;`);
 const shadow=(await db.query(capture)).rows[0];assert.equal(shadow.display,'synthetic_display()');assert.equal(shadow.source_md5,fixed.source_md5);assert.notEqual(shadow.namespace,fixed.namespace);
 await db.exec('SET search_path=public;');const shadowFixed=(await db.query(capture)).rows[0];assert.equal(shadowFixed.display,'shadow.synthetic_display()');assert.notEqual(shadowFixed.display,fixed.display);
 await db.exec(`CREATE OR REPLACE FUNCTION shadow.synthetic_display() RETURNS event_trigger LANGUAGE plpgsql AS $$BEGIN PERFORM 1;END$$;`);const changed=(await db.query(capture)).rows[0];assert.notEqual(changed.source_md5,fixed.source_md5);
 await db.exec(`REVOKE EXECUTE ON FUNCTION shadow.synthetic_display() FROM PUBLIC;`);const acl=(await db.query(capture)).rows[0];assert.notDeepEqual(acl.acl,changed.acl);
 console.log('PASS PostgreSQL17 search_path display reproduction/fix, physical same-name same-body shadow distinction, source/ACL drift distinction; native proof=false');
}finally{await db.close();}
