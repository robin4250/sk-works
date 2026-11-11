from pathlib import Path
import os

source = Path(os.environ['SKO_PREVIEW_WRAPPER']).read_text()
injection = r'''
await db.exec("create table if not exists public.member_feature_permissions(company_id uuid,user_id uuid,can_manage_invoices boolean);");
await db.exec(${JSON.stringify(stageCandidate)});
await db.exec("update invoice_revision_candidate.settings set enabled=true");
const revisionCommand=id(994);
const stageCall=(source,original)=>db.query('select invoice_revision_candidate.stage($1,$2,$3,$4,$5) v',[frozen.id,revisionCommand,source,original,'２日分の勤務記録を反映']);
await assert.rejects(stageCall('b'.repeat(64),correctionPreview.original_invoice_fingerprint),/revision_preview_invalid_or_changed/);
const firstStage=(await stageCall(correctionPreview.source_fingerprint,correctionPreview.original_invoice_fingerprint)).rows[0].v;
assert.equal(firstStage.replayed,false);
assert.equal((await stageCall(correctionPreview.source_fingerprint,correctionPreview.original_invoice_fingerprint)).rows[0].v.replayed,true);
const staged=(await db.query('select original_record,proposed_snapshot,grand_total from invoice_revision_candidate.proposals where id=$1',[revisionCommand])).rows[0];
assert.deepEqual(staged.proposed_snapshot,correctionPreview.proposed_snapshot);
assert.equal(Number(staged.grand_total),correctionPreview.grand_total);
await db.exec('create table private.master_admins(user_id uuid primary key,enabled boolean)');
await db.query('insert into private.master_admins values($1,true)',[actor]);
await db.exec(${JSON.stringify(ownerCandidate)});
await assert.rejects(db.query('select invoice_owner_preview_candidate.read($1)',[frozen.id]),/preview_disabled/);
await db.exec('update invoice_owner_preview_candidate.settings set enabled=true');
const ownerPreview=(await db.query('select invoice_owner_preview_candidate.read($1) v',[frozen.id])).rows[0].v;
assert.equal(ownerPreview.status,'unissued_reference_only');
assert.deepEqual(ownerPreview.snapshot,correctionPreview.proposed_snapshot);
assert.equal(Number(ownerPreview.grand_total),correctionPreview.grand_total);
await db.exec('update private.master_admins set enabled=false');
await assert.rejects(db.query('select invoice_owner_preview_candidate.read($1)',[frozen.id]),/preview_unavailable/);
const review=(await db.query('select invoice_revision_candidate.read_prepared($1) v',[revisionCommand])).rows[0].v;
assert.equal(review.status,'review_only');assert.deepEqual(review.proposed_snapshot,correctionPreview.proposed_snapshot);
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
console.log(JSON.stringify({staged_trusted_preview:true,original_invoice_untouched:true,full_totals_match:true}));
'''
marker = "console.log(JSON.stringify({invoice_correction_preview:true"
assert source.count(marker) == 1
source = source.replace("const marker='let checks=0;'", "const stageCandidate=await readFile(resolve(process.env.SKO_STAGE_SQL),'utf8');\nconst ownerCandidate=await readFile(resolve(process.env.SKO_OWNER_PREVIEW_SQL),'utf8');\nconst marker='let checks=0;'")
source = source.replace(marker, injection + marker)
target = Path(os.environ['SKO_ADJUSTMENT_ROOT']) / 'tool/verify_invoice_preview_stage_wrapper.generated.mjs'
target.write_text(source)
print(target)
