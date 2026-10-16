import fs from 'node:fs/promises';import path from 'node:path';import test from 'node:test';import assert from 'node:assert/strict';
import {instrumentSessionLifecycle} from './auth_session_lifecycle_runner.mjs';
const source=await fs.readFile(path.resolve('tool/security/platform_auth_gotrue_e2e.mjs'),'utf8');
const config={adapterUrl:'file:///fixture/platform_log_adapter.mjs',checkUrl:'file:///fixture/auth_session_lifecycle_check.mjs'};
test('reuse preserves every original assertion and cleanup; one hook only',()=>{
 const output=instrumentSessionLifecycle(source,config);
 assert.equal(output.split('await __verifySessionLifecycle(').length-1,1);
 const original=output.replace(/^import \{verifySessionLifecycle as __verifySessionLifecycle\} from .*;\n/,'')
 .replace('import {sanitizePlatformRows} from "file:///fixture/platform_log_adapter.mjs";',"import {sanitizePlatformRows} from './platform_log_adapter.mjs';")
 .replace(" phase='real-session-lifecycle';\n await __verifySessionLifecycle({request,db,password,claims,guardedSessions:[master,normalAdmin,other]});\n",'');
 assert.equal(original,source,'Only a local import and extra hook may differ');
});
test('source and missing/duplicate anchor drift abort before setup',()=>{
 for(const changed of [source+'\n',source.replace(" phase='original-app-fixtures';",''),source+" phase='original-app-fixtures';"]){assert.throws(()=>instrumentSessionLifecycle(changed,config),/drift/);}
});
test('remote helper import refused',()=>assert.throws(()=>instrumentSessionLifecycle(source,{...config,checkUrl:'https://example.invalid/hook.mjs'}),/local files/));
