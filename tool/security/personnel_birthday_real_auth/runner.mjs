// Reuse the established disposable stack owner; never accepts hosted endpoints.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=process.cwd();
const source=await fs.readFile('tool/company_checkout_real_gotrue_e2e.mjs','utf8');
const start=" phase='unchanged-checkout-foundation';",end='}catch(error){';
assert.equal(source.split(start).length,2,'Disposable runner setup anchor changed');
assert.equal(source.split(end).length,2,'Disposable runner cleanup anchor changed');
let prefix=source.split(start)[0];
const moduleAnchor="path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js')";
assert.equal(prefix.split(moduleAnchor).length,2);
prefix=prefix.replace(moduleAnchor,"(process.env.SKO_PERSONNEL_BIRTHDAY_PG_MODULE??path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))");
// Keep normal isolated token lifetime; expiry negatives concern proof validity.
const expiryAnchor=" config=config.replace(/^jwt_expiry = .*$/m,'jwt_expiry = 60');";
assert.equal(prefix.split(expiryAnchor).length,2);prefix=prefix.replace(expiryAnchor,'');
const fixtureUrl=pathToFileURL(path.join(root,'tool/security/personnel_birthday_real_auth/fixture.mjs')).href;
const body=`
 phase='personnel-birthday-isolated-contract';
 await (await import(${JSON.stringify(fixtureUrl)})).verifyPersonnelBirthdayRealAuth({db,api,publicKey,serviceKey,users,sessions,password,request,rpc,eq});
 eq((await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) value")).rows[0].value,authUidBefore);
 console.log(JSON.stringify({pass:true,checks,real_gotrue:true,real_postgrest:true,synthetic_application_fixture:true,production_changed:false}));
`;
const guard="if(process.env.CI!=='true'||process.env.SKO_PERSONNEL_BIRTHDAY_REAL_AUTH!=='contract-v1')throw Error('Dedicated personnel birthday isolated hook required');\n";
const generated=guard+prefix+body+end+source.split(end)[1];
const directory=await fs.mkdtemp(path.join(os.tmpdir(),'personnel-birthday-real-auth-'));
try{
 const file=path.join(directory,'proof.mjs');await fs.writeFile(file,generated,{mode:0o600});
 const syntax=spawnSync(process.execPath,['--check',file],{encoding:'utf8'});assert.equal(syntax.status,0,'Generated isolated runner syntax');
 if(process.argv.includes('--check-generated'))console.log('PASS existing disposable runner setup/cleanup anchors and generated personnel birthday runner syntax');
 else{const result=spawnSync(process.execPath,[file],{cwd:root,stdio:'inherit',env:process.env});if(result.error)throw result.error;process.exitCode=result.status??1;}
}finally{await fs.rm(directory,{recursive:true,force:true});}
