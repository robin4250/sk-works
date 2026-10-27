// TEST ONLY. This fixture is never a production route and contains no real key.
import {rotateAuthorityFixture,verifyRotationHistoryFixture} from '../src/anchor-rotation-fixture.mjs';
import {initializeAnchorAuthority,preserveIndependentAnchor,latestIndependentAnchor} from '../src/anchor-authority.mjs';
import {initializeNoticeArchive,storeNoticeArchive,storeNoticeArchiveWithContinuity,readNoticeArchive,readNoticeArchiveWithContinuity} from '../src/notice-archive.mjs';
export class ArchiveFixture{
 constructor(ctx){this.ctx=ctx;}
 async fetch(request){const path=new URL(request.url).pathname,s=this.ctx.storage,input=await request.json();try{
  if(path==='/initialize')return Response.json(initializeNoticeArchive(s,input));
  if(path==='/store')return Response.json(await storeNoticeArchive(s,input));
  if(path==='/store-strict')return Response.json(await storeNoticeArchiveWithContinuity(s,input));
  if(path==='/read-strict')return Response.json(await readNoticeArchiveWithContinuity(s,input));
  if(path==='/tamper-extension') {s.sql.exec('UPDATE notice_archive_extensions SET rows_json=? WHERE batch_sequence=?',input.rows,input.sequence);return Response.json(true);}
  if(path==='/delete-extension') {s.sql.exec('DELETE FROM notice_archive_extensions WHERE batch_sequence=?',input.sequence);return Response.json(true);}
  if(path==='/read')return Response.json(await readNoticeArchive(s,input));
  if(path==='/extensions')return Response.json(s.sql.exec('SELECT * FROM notice_archive_extensions ORDER BY batch_sequence').toArray());
  if(path==='/fail-extension') {s.sql.exec("CREATE TRIGGER injected_extension_failure BEFORE INSERT ON notice_archive_extensions BEGIN SELECT RAISE(ABORT,'fixture extension failure');END");return Response.json(true);}
  if(path==='/snapshot')return Response.json({state:s.sql.exec('SELECT * FROM notice_archive_state').toArray(),rows:s.sql.exec('SELECT * FROM notice_archive_batches ORDER BY sequence').toArray()});
  if(path==='/tamper') {s.sql.exec('UPDATE notice_archive_batches SET manifest=? WHERE sequence=?',input.manifest,input.sequence);return Response.json(true);}
  if(path==='/delete') {s.sql.exec('DELETE FROM notice_archive_batches WHERE sequence=?',input.sequence);return Response.json(true);}
  if(path==='/fail') {s.sql.exec("CREATE TRIGGER injected_failure BEFORE INSERT ON notice_archive_batches BEGIN SELECT RAISE(ABORT,'fixture failure');END");return Response.json(true);}
 }catch(e){return Response.json({error:e.message},{status:409});}return new Response(null,{status:404});}
}
export class AuthorityFixture{
 constructor(ctx,env){this.ctx=ctx;this.env=env;}
 async fetch(request){const path=new URL(request.url).pathname,s=this.ctx.storage,input=await request.json();try{
  if(path==='/initialize')return Response.json(initializeAnchorAuthority(s,input));
  if(path==='/rotate')return Response.json(await rotateAuthorityFixture(s,{...input,oldKey:await crypto.subtle.importKey('jwk',input.oldKey,'Ed25519',false,['sign']),newKey:await crypto.subtle.importKey('jwk',input.newKey,'Ed25519',false,['sign'])}));
  if(path==='/rotation-history')return Response.json(await verifyRotationHistoryFixture(s,input));
  if(path==='/rotation-tamper'){s.sql.exec('UPDATE anchor_rotation_history SET old_signature=? WHERE id=1',input.value);return Response.json(true);}
  if(path==='/rotation-fail'){s.sql.exec("CREATE TRIGGER rotation_failure BEFORE UPDATE ON anchor_authority BEGIN SELECT RAISE(ABORT,'fixture fail');END");return Response.json(true);}
  if(path==='/publish-with-key')return Response.json(await preserveIndependentAnchor(s,{publication:input.publication,now:input.now,anchorKey:await crypto.subtle.importKey('jwk',input.key,'Ed25519',false,['sign'])}));
  if(path==='/publish')return Response.json(await preserveIndependentAnchor(s,{...input,anchorKey:await crypto.subtle.importKey('jwk',JSON.parse(this.env.FIXTURE_ANCHOR_PRIVATE),'Ed25519',false,['sign'])}));
  if(path==='/latest')return Response.json(await latestIndependentAnchor(s));
 }catch(e){return Response.json({error:e.message},{status:409});}return new Response(null,{status:404});}
}
export default{fetch:()=>new Response(null,{status:404})};
