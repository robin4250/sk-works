// Reuse the reviewed PR829 fixture without duplicating its completed assertions.
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
const baseline = execFileSync('git', ['show', '46f7099482f5fa203613873b8dbd2469a3f612a0:tool/verify_capture_management_retention.mjs'], {encoding:'utf8'});
const baselineSql = execFileSync('git', ['show', '0ba3d120199e5fd43caad9967e20f958fe7d17e0:supabase/tests/attendance_capture_management_retention_assertions.sql'], {encoding:'utf8'});
if (!baseline.includes('await db.exec(assertions.slice(split));')) throw new Error('baseline boundary changed; review before execution');
const source = baseline.replace("import fs from 'node:fs';", '')
 .replace("const { PGlite } = await import(process.argv[2]);", '')
 .replace("fs.readFileSync('supabase/tests/attendance_capture_management_retention_assertions.sql', 'utf8')", 'baselineSql')
 .replace('await db.exec(assertions.slice(split));', "await db.exec(assertions.slice(split)); await db.exec(fs.readFileSync('supabase/tests/capture_retention_boundaries.sql','utf8'));")
 .replace('PASS existing management loss reproduced; fixture-only archive preserves original capture/report, atomic failure and rollback', 'PASS additional isolated boundaries: deleted UUID replay gap, archive UUID rejection, child snapshot before cascade, actual actor');
const {PGlite} = await import(process.argv[2]);
await new (Object.getPrototypeOf(async function(){}).constructor)('fs','PGlite','baselineSql',source)(fs,PGlite,baselineSql);
