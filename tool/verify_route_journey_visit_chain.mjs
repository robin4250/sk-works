import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
// Reuse the existing regression setup and assertions; no copied alternate
// implementations of actual GPS date/capture guards or management functions.
const baseline=fs.readFileSync('tool/verify_attendance_capture_failure.mjs','utf8');
const anchor="  console.log('PASS attendance capture failures and existing GPS shift/RLS/management assertions');";
assert.ok(baseline.includes(anchor),'existing regression hook changed');
const additions=[
 'tool/fixtures/route_journey_visits/chain_assertions.sql',
 'supabase/migrations/20260920210500_restrict_attendance_evidence_privacy.sql',
 'tool/fixtures/route_journey_visits/photo_path_regression.sql',
 'supabase/migrations/20261010133056_qualify_attendance_photo_upload_path.sql',
 'tool/fixtures/route_journey_visits/photo_path_fixed.sql',
 'supabase/migrations/20261008204012_route_journey_capture_staged.sql',
 'supabase/migrations/20261010132957_route_journey_visit_lifecycle.sql',
 'tool/fixtures/route_journey_visits/chain_flow.sql',
].map(p=>fs.readFileSync(p,'utf8'));
const source=baseline.replace("import fs from 'node:fs';",'')
 .replace('const { PGlite } = await import(process.argv[2]);','')
 .replace(anchor,"  for(const sql of additions) await db.exec(sql);\n  console.log('PASS real GPS/capture/management regressions plus visit start/end/clock-out/archive chain');");
await new (Object.getPrototypeOf(async function(){}).constructor)('fs','PGlite','additions',source)(fs,PGlite,additions);
