import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const review=fs.readFileSync('tool/verify_expense_review_allocation.mjs','utf8');
const marker=" console.log('PASS expense-specific assignees, approve to own company, allocation, rejected details, fixed command retries, version conflicts and unchanged other-page assignees');";
assert.ok(review.includes(marker));
const assertions=fs.readFileSync('tool/fixtures/expense_settlement_choice_assertions.mjs','utf8');
const escaped=assertions.replaceAll('\\','\\\\').replaceAll('`','\\`').replaceAll('${','\\${');
const source=review.replace(marker,escaped)
 .replace("import fs from 'node:fs';",'').replace("import assert from 'node:assert/strict';",'')
 .replace('const {PGlite}=await import(process.argv[2]);','');
await new (Object.getPrototypeOf(async function(){}).constructor)('fs','assert','PGlite',source)(fs,assert,PGlite);
