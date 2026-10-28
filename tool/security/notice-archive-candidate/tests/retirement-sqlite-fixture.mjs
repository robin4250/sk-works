// SYNTHETIC TEST ONLY: one SQLite Durable Object, no authentication,
// independent custody, production endpoint, network or real data.
const hex=a=>Array.from(new Uint8Array(a),x=>x.toString(16).padStart(2,'0')).join('');
const sha=async s=>hex(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)));
const get=(sql,q,...a)=>sql.exec(q,...a).toArray()[0];
export class Ledger {
 constructor(ctx){this.s=ctx.storage;this.s.sql.exec('CREATE TABLE IF NOT EXISTS live(id TEXT PRIMARY KEY, snapshot TEXT NOT NULL)');this.s.sql.exec('CREATE TABLE IF NOT EXISTS history(id TEXT PRIMARY KEY, snapshot TEXT NOT NULL, digest TEXT NOT NULL)');this.s.sql.exec('CREATE TABLE IF NOT EXISTS tombstone(id TEXT PRIMARY KEY, digest TEXT NOT NULL)');}
 async fetch(req){const path=new URL(req.url).pathname,x=await req.json(),sql=this.s.sql;try{
  if(path==='/put'){if(!x.id||typeof x.snapshot!=='string'||x.snapshot.length>8192)throw Error('invalid fixture');sql.exec('INSERT INTO live VALUES(?,?)',x.id,x.snapshot);return Response.json(true);}
  if(path==='/prepare'){const row=get(sql,'SELECT snapshot FROM live WHERE id=?',x.id);if(!row)throw Error('missing fixture');return Response.json({id:x.id,snapshot:row.snapshot,digest:await sha(row.snapshot)});}
  if(path==='/retire'){
   if(typeof x.snapshot!=='string'||await sha(x.snapshot)!==x.digest)throw Error('snapshot mismatch');
   const result=this.s.transactionSync(()=>{
    const old=get(sql,'SELECT digest FROM tombstone WHERE id=?',x.id);if(old){if(old.digest!==x.digest)throw Error('retry conflict');return {replayed:true};}
    const row=get(sql,'SELECT snapshot FROM live WHERE id=?',x.id);if(!row||row.snapshot!==x.snapshot)throw Error('source changed');
    // Kept in same fixture DB to exercise atomic rollback only; it is NOT an
    // independent signed archive or safe authority to unpin real evidence.
    sql.exec('INSERT INTO history VALUES(?,?,?)',x.id,row.snapshot,x.digest);
    sql.exec('INSERT INTO tombstone VALUES(?,?)',x.id,x.digest);
    sql.exec('DELETE FROM live WHERE id=?',x.id);
    return {replayed:false};
   });return Response.json(result);
  }
  if(path==='/read'){const row=get(sql,'SELECT snapshot,digest FROM history WHERE id=?',x.id);if(!row||await sha(row.snapshot)!==row.digest)throw Error('history missing or corrupt');return Response.json(row);}
  if(path==='/change'){sql.exec('UPDATE live SET snapshot=? WHERE id=?',x.snapshot,x.id);return Response.json(true);}
  if(path==='/fail'){sql.exec("CREATE TRIGGER injected BEFORE INSERT ON tombstone BEGIN SELECT RAISE(ABORT,'synthetic failure'); END");return Response.json(true);}
  if(path==='/snapshot')return Response.json({live:sql.exec('SELECT * FROM live ORDER BY id').toArray(),history:sql.exec('SELECT * FROM history ORDER BY id').toArray(),tombstones:sql.exec('SELECT * FROM tombstone ORDER BY id').toArray()});
 }catch(e){return Response.json({error:e.message},{status:409});}return new Response(null,{status:404});}
}
export default{fetch:()=>new Response(null,{status:404})};
