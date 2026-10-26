// TEST ONLY. Never publish these key/inspection routes.
import {initializeAnchorAuthority,preserveIndependentAnchor,latestIndependentAnchor} from '../src/anchor-authority.mjs';
export class AnchorFixture{
 constructor(ctx,env){this.ctx=ctx;this.env=env;}
 async fetch(request){
  const p=new URL(request.url).pathname,s=this.ctx.storage,b=await request.json();
  try{
   if(p==='/initialize')return Response.json(initializeAnchorAuthority(s,b));
   if(p==='/publish')return Response.json(await preserveIndependentAnchor(s,{...b,anchorKey:await crypto.subtle.importKey('jwk',JSON.parse(this.env.FIXTURE_ANCHOR_PRIVATE),'Ed25519',false,['sign'])}));
   if(p==='/latest')return Response.json(await latestIndependentAnchor(s));
   if(p==='/snapshot')return Response.json({state:s.sql.exec('SELECT * FROM anchor_authority').toArray(),receipts:s.sql.exec('SELECT * FROM anchor_receipts ORDER BY sequence').toArray()});
   if(p==='/fail-insert'){s.sql.exec("CREATE TRIGGER fail_anchor BEFORE INSERT ON anchor_receipts BEGIN SELECT RAISE(ABORT,'synthetic failure');END");return Response.json(true);}
   if(p==='/tamper'){s.sql.exec('UPDATE anchor_authority SET hash=? WHERE id=1','f'.repeat(64));return Response.json(true);}
  }catch(e){return Response.json({error:e.message},{status:409});}
  return new Response(null,{status:404});
 }
}
export {ManagementFixture as SourceFixture} from './management-fixture.mjs';
export default{fetch:()=>new Response(null,{status:404})};
