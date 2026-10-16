import fs from 'node:fs/promises';import path from 'node:path';import test from 'node:test';import assert from 'node:assert/strict';
import {instrumentSessionLifecycle} from './auth_session_lifecycle_runner.mjs';
const source=await fs.readFile(path.resolve('tool/security/platform_auth_gotrue_e2e.mjs'),'utf8');
const config={adapterUrl:'file:///fixture/platform_log_adapter.mjs',checkUrl:'file:///fixture/auth_session_lifecycle_check.mjs',configUrl:'file:///fixture/auth_session_lifecycle_local_config.mjs'};
test('reuse preserves every original assertion and cleanup; one hook only',()=>{
 const output=instrumentSessionLifecycle(source,config);
 assert.equal(output.split('await __verifySessionLifecycle(').length-1,1);
 const original=output.replace(/^import \{configureLocalPhoneFixture as __configureLocalPhoneFixture\} from .*;\n/,'').replace(' config=await __configureLocalPhoneFixture(config,{owns,workdir,parent,project,configPath});\n','').replace(/^import \{verifySessionLifecycle as __verifySessionLifecycle\} from .*;\n/,'')
 .replace('import {sanitizePlatformRows} from "file:///fixture/platform_log_adapter.mjs";',"import {sanitizePlatformRows} from './platform_log_adapter.mjs';")
 .replace(" phase='real-session-lifecycle';\n await __verifySessionLifecycle({request,db,password,claims,guardedSessions:[master,normalAdmin,other]});\n",'');
 assert.equal(original,source,'Only a local import and extra hook may differ');
});
test('source and missing/duplicate anchor drift abort before setup',()=>{
 for(const changed of [source+'\n',source.replace(" phase='original-app-fixtures';",''),source+" phase='original-app-fixtures';"]){assert.throws(()=>instrumentSessionLifecycle(changed,config),/drift/);}
});
test('remote helper import refused',()=>assert.throws(()=>instrumentSessionLifecycle(source,{...config,checkUrl:'https://example.invalid/hook.mjs'}),/local files/));

test('synthetic phone route allowlist refuses SMS/OTP/provider and real numbers',async()=>{
 const {assertPhoneLifecycleRequest}=await import('./auth_session_lifecycle_check.mjs');
 const phone='+12025550123';
 assert.doesNotThrow(()=>assertPhoneLifecycleRequest('/auth/v1/admin/users',{service:true,body:{phone,password:'synthetic-test-only',phone_confirm:true}}));
 assert.doesNotThrow(()=>assertPhoneLifecycleRequest('/auth/v1/token?grant_type=password',{body:{phone,password:'synthetic-test-only'}}));
 for(const route of ['/auth/v1/otp','/auth/v1/verify','/auth/v1/signup','/auth/v1/resend','/auth/v1/recover','/auth/v1/settings','https://example.invalid/auth/v1/token?grant_type=password']){
  assert.throws(()=>assertPhoneLifecycleRequest(route,{body:{phone,password:'synthetic-test-only'}}),/permits/);
 }
 assert.throws(()=>assertPhoneLifecycleRequest('/auth/v1/admin/users',{service:true,body:{phone,password:'synthetic-test-only',phone_confirm:false}}),/permits/);
 assert.throws(()=>assertPhoneLifecycleRequest('/auth/v1/token?grant_type=password',{body:{phone:'+10000000000',password:'synthetic-test-only'}}),/permits/);
});

const phoneConfig=`project_id = "sko-platform-proof-0000000000000000"
[auth.sms]
enable_signup = false
enable_confirmations = false
template = "Your code is {{ .Code }}"
max_frequency = "5s"
[auth.sms.twilio]
enabled = false
account_sid = ""
message_service_sid = ""
auth_token = "env(SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN)"
`;
test('only isolated phone flag changes; SMS confirmations/transport/credentials remain absent',async()=>{
 const {patchLocalPhoneConfig}=await import('./auth_session_lifecycle_local_config.mjs');
 const result=patchLocalPhoneConfig(phoneConfig);
 assert.equal(result.replace('enable_signup = true','enable_signup = false'),phoneConfig);
 for(const changed of [phoneConfig+'[auth.sms]\nenable_signup = false\n',phoneConfig.replace('enable_signup = false','enable_signup = true'),phoneConfig.replace('enable_confirmations = false','enable_confirmations = true'),phoneConfig.replace('enabled = false','enabled = true'),phoneConfig.replace('account_sid = ""','account_sid = "unexpected"'),phoneConfig+'[auth.sms.unexpected]\nenabled = false\n',phoneConfig.replace('enable_confirmations = false','enable_confirmations = false\nenable_confirmations = true'),phoneConfig.replace('enabled = false','enabled = false\nenabled = true'),phoneConfig.replace('account_sid = ""','account_sid = ""\naccount_sid = "unexpected"'),phoneConfig.replace('auth_token =','auth_token = "unexpected"\nauth_token =')]){
  assert.throws(()=>patchLocalPhoneConfig(changed));
 }
});
test('phone config cannot target unowned or symlinked directories; original file remains untouched',async()=>{
 const os=await import('node:os');const {configureLocalPhoneFixture}=await import('./auth_session_lifecycle_local_config.mjs');
 const parent=await fs.mkdtemp(path.join(os.tmpdir(),'sko-phone-owner-test-')),project='sko-platform-proof-0000000000000000',workdir=path.join(parent,project),configPath=path.join(workdir,'supabase/config.toml');
 try{
  await fs.mkdir(path.join(workdir,'supabase'),{recursive:true});await fs.chmod(workdir,0o700);
  await fs.writeFile(path.join(workdir,'owned-fixture.json'),JSON.stringify({project,ports:[53920,53921,53922]}));await fs.writeFile(configPath,phoneConfig);
  const args={owns:true,workdir,parent,project,configPath};
  const modified=await configureLocalPhoneFixture(phoneConfig,args);assert.ok(modified.includes('enable_signup = true'));assert.equal(await fs.readFile(configPath,'utf8'),phoneConfig);
  await assert.rejects(configureLocalPhoneFixture(phoneConfig,{...args,owns:false}));
  await assert.rejects(configureLocalPhoneFixture(phoneConfig,{...args,configPath:path.join(parent,'other.toml')}));
  await fs.writeFile(path.join(parent,'other.toml'),phoneConfig);await fs.unlink(configPath);await fs.symlink(path.join(parent,'other.toml'),configPath);
  await assert.rejects(configureLocalPhoneFixture(phoneConfig,args),/Symlinked/);
 }finally{await fs.rm(parent,{recursive:true,force:true});}
});
