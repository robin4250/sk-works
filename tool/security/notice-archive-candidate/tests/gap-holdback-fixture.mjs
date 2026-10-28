// Synthetic-only bounded holdback design; NOT an authenticated endpoint,
// source-HMAC verifier, SQL migration, real alert, or deployable code.
const get=(sql,q,...args)=>sql.exec(q,...args).toArray()[0];
export class GapLedger{
 constructor(ctx){this.s=ctx.storage;let q=this.s.sql;q.exec('CREATE TABLE IF NOT EXISTS control(id INTEGER PRIMARY KEY,recipient TEXT NOT NULL,revision INTEGER NOT NULL)');q.exec("INSERT OR IGNORE INTO control VALUES(1,'fixture-owner-a',1)");q.exec('CREATE TABLE IF NOT EXISTS source(id TEXT PRIMARY KEY,body TEXT NOT NULL,recipient TEXT NOT NULL,revision INTEGER NOT NULL,notification_state TEXT NOT NULL)');q.exec('CREATE TABLE IF NOT EXISTS outbox(id TEXT PRIMARY KEY,recipient TEXT NOT NULL,revision INTEGER NOT NULL)');q.exec('CREATE TABLE IF NOT EXISTS counters(id INTEGER PRIMARY KEY,gaps INTEGER NOT NULL,refusals INTEGER NOT NULL)');q.exec('INSERT OR IGNORE INTO counters VALUES(1,0,0)');}
 async fetch(req){const path=new URL(req.url).pathname,x=await req.json(),q=this.s.sql;try{
 if(path==='/configure'){q.exec('UPDATE control SET recipient=?,revision=? WHERE id=1',x.recipient,x.revision);return Response.json(true);}
 if(path==='/receive')return Response.json(this.s.transactionSync(()=>{
  const old=get(q,'SELECT * FROM source WHERE id=?',x.id);if(old){if(old.body!==x.body)throw Error('conflicting source retry');return {replayed:true,state:old.notification_state};}
  const c=get(q,'SELECT * FROM control WHERE id=1');if(get(q,'SELECT COUNT(*) AS n FROM source').n>=3){q.exec('UPDATE counters SET refusals=refusals+1 WHERE id=1');return {accepted:false,reason:'source_capacity'};}
  const full=get(q,'SELECT COUNT(*) AS n FROM outbox').n>=1,state=full?'held_capacity':'queued';
  q.exec('INSERT INTO source VALUES(?,?,?,?,?)',x.id,x.body,c.recipient,c.revision,state);
  if(full)q.exec('UPDATE counters SET gaps=gaps+1 WHERE id=1');else q.exec('INSERT INTO outbox VALUES(?,?,?)',x.id,c.recipient,c.revision);
  return {accepted:true,state};
 }));
 if(path==='/backfill')return Response.json(this.s.transactionSync(()=>{
  const e=get(q,'SELECT * FROM source WHERE id=?',x.id),c=get(q,'SELECT * FROM control WHERE id=1');if(!e||e.notification_state!=='held_capacity')throw Error('not held');
  // Fixture comparison models a current authorization check only; real Master
  // and company checks, locking, auth and config change management are absent.
  if(e.recipient!==c.recipient||e.revision!==c.revision)return {state:'held_binding'};
  if(get(q,'SELECT COUNT(*) AS n FROM outbox').n>=1)return {state:'held_capacity'};
  q.exec('INSERT INTO outbox VALUES(?,?,?)',e.id,e.recipient,e.revision);q.exec("UPDATE source SET notification_state='queued' WHERE id=?",e.id);return {state:'queued'};
 }));
 if(path==='/archive-fixture')return Response.json(this.s.transactionSync(()=>{const e=get(q,'SELECT * FROM source WHERE id=?',x.id);if(!e||e.notification_state!=='queued')throw Error('not queued');q.exec('DELETE FROM outbox WHERE id=?',x.id);q.exec("UPDATE source SET notification_state='archived_fixture' WHERE id=?",x.id);return true;}));
 if(path==='/purge-fixture')return Response.json(this.s.transactionSync(()=>{const e=get(q,'SELECT * FROM source WHERE id=?',x.id);if(!e||e.notification_state!=='archived_fixture')throw Error('source pinned');q.exec('DELETE FROM source WHERE id=?',x.id);return true;}));
 if(path==='/snapshot')return Response.json({source:q.exec('SELECT * FROM source ORDER BY id').toArray(),outbox:q.exec('SELECT * FROM outbox ORDER BY id').toArray(),counters:get(q,'SELECT * FROM counters WHERE id=1')});
 }catch(e){return Response.json({error:e.message},{status:409})}return new Response(null,{status:404});}
}
export default{fetch:()=>new Response(null,{status:404})};
