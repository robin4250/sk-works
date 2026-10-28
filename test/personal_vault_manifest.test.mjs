import {test} from 'node:test';
import assert from 'node:assert/strict';
import {planOwnArchive,verifyArchiveCompletion} from '../tool/personal_vault_manifest.mjs';
const context={enabled:true,sessionVerified:true,personId:'person-fixture',sourceCompanyId:'company-fixture',cutoff:'2026-10-27'};
const record={kind:'own_attendance',personId:context.personId,sourceCompanyId:context.sourceCompanyId,sourceId:'attendance-fixture',revision:'rev1',periodStart:'2026-10-01',periodEnd:'2026-10-27',immutable:true,finalized:true,snapshotSha256:'a'.repeat(64)};
const inventory=records=>({...context,complete:true,records});
const receipt=(p,r)=>({artifactKey:r.artifactKey,personId:p.personId,sourceCompanyId:p.sourceCompanyId,snapshotSha256:r.snapshotSha256,status:'verified',contentType:'application/pdf',byteLength:42,pdfSha256:'b'.repeat(64),immutableVersion:'version1'});
test('same immutable source has deterministic key across transitions and ordering',()=>{
 const payroll={...record,kind:'own_payroll',sourceId:'payroll-fixture'};
 const a=planOwnArchive(context,inventory([record,payroll])); const b=planOwnArchive(context,inventory([payroll,record]));
 assert.deepEqual(a,b);assert.equal(verifyArchiveCompletion(a,a.records.map(r=>receipt(a,r))).count,2);
 const changed=planOwnArchive(context,inventory([{...record,revision:'rev2'}]));assert.notEqual(changed.records[0].artifactKey,a.records.find(r=>r.kind==='own_attendance').artifactKey);
});
test('reject foreign person/company, internal material, unfinished and out-of-range snapshots',()=>{
 for(const patch of [{personId:'other'},{sourceCompanyId:'other'},{kind:'resume'},{finalized:false},{immutable:false},{periodEnd:'2026-10-28'},{periodEnd:'2026-02-30'}]) assert.throws(()=>planOwnArchive(context,inventory([{...record,...patch}])));
 assert.throws(()=>planOwnArchive({...context,enabled:false},inventory([record])));
 assert.throws(()=>planOwnArchive({...context,sessionVerified:false},inventory([record])));
 assert.throws(()=>planOwnArchive(context,{...inventory([record]),complete:false}));
 assert.throws(()=>planOwnArchive(context,inventory([record,{...record,revision:'rev2'}])));
});
test('missing, duplicate, foreign, changed or failed files never count as completed',()=>{
 const p=planOwnArchive(context,inventory([record]));const good=receipt(p,p.records[0]);
 assert.throws(()=>verifyArchiveCompletion(p,[]));assert.throws(()=>verifyArchiveCompletion(p,[good,good]));
 for(const patch of [{personId:'other'},{sourceCompanyId:'other'},{snapshotSha256:'c'.repeat(64)},{status:'failed'},{byteLength:0},{immutableVersion:null}]) assert.throws(()=>verifyArchiveCompletion(p,[{...good,...patch}]));
});
