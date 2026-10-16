import fs from 'node:fs/promises';
import path from 'node:path';
function section(config,name){
 const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
 const header=new RegExp(`^\\[${escaped}\\]\\n`,'gm'),matches=[...config.matchAll(header)];
 if(matches.length!==1)throw Error('Local phone fixture config section drift');
 const start=matches[0].index,endStart=start+matches[0][0].length;
 const next=/^\[/gm;next.lastIndex=endStart;const end=next.exec(config)?.index??config.length;
 return {start,end,text:config.slice(start,end)};
}
export function patchLocalPhoneConfig(config){
 const sms=section(config,'auth.sms'),twilio=section(config,'auth.sms.twilio');
 const providers=[...config.matchAll(/^\[auth\.sms\.([^\]]+)\]$/gm)].map(x=>x[1]);
 if(providers.length!==1||providers[0]!=='twilio')throw Error('Unknown SMS provider refused');
 for(const [block,line] of [[sms.text,'enable_signup = false'],[sms.text,'enable_confirmations = false'],[twilio.text,'enabled = false'],[twilio.text,'account_sid = ""'],[twilio.text,'message_service_sid = ""'],[twilio.text,'auth_token = "env(SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN)"']]){
  const key=line.split(' = ')[0];
  if(block.split('\n').filter(x=>new RegExp(`^\\s*${key}\\s*=`).test(x)).length!==1||block.split('\n').filter(x=>x===line).length!==1)throw Error('SMS transport/credential/default configuration refused');
 }
 if(Object.keys(process.env).some(k=>/^SUPABASE_/.test(k)))throw Error('Hosted or SMS credential environment refused');
 const patched=sms.text.replace('\nenable_signup = false\n','\nenable_signup = true\n');
 if(patched===sms.text)throw Error('Phone fixture single setting replacement failed');
 const result=config.slice(0,sms.start)+patched+config.slice(sms.end);
 const changed=section(result,'auth.sms');
 if(changed.text.split('\n').filter(x=>x==='enable_signup = true').length!==1||changed.text.replace('\nenable_signup = true\n','\nenable_signup = false\n')!==sms.text||section(result,'auth.sms.twilio').text!==twilio.text)throw Error('Phone fixture postcondition drift');
 return result;
}
export async function configureLocalPhoneFixture(config,{owns,workdir,parent,project,configPath}){
 if(owns!==true||!/^sko-platform-proof-[0-9a-f]{16}$/.test(project))throw Error('Owned original fixture required');
 const resolvedParent=path.resolve(parent),resolvedWork=path.resolve(workdir),resolvedConfig=path.resolve(configPath);
 if(resolvedParent==='/'||resolvedWork!==path.join(resolvedParent,project)||resolvedConfig!==path.join(resolvedWork,'supabase/config.toml'))throw Error('Nonowned config location refused');
 if(await fs.realpath(workdir)!==resolvedWork||await fs.realpath(configPath)!==resolvedConfig)throw Error('Symlinked fixture config refused');
 const stat=await fs.stat(workdir);if(!stat.isDirectory()||(stat.mode&0o077)!==0)throw Error('Private fixture workdir required');
 const marker=JSON.parse(await fs.readFile(path.join(workdir,'owned-fixture.json'),'utf8'));
 if(marker.project!==project||JSON.stringify(marker.ports)!=='[53920,53921,53922]')throw Error('Original fixture ownership marker mismatch');
 if(!config.includes(`project_id = "${project}"`))throw Error('Local fixture project identity mismatch');
 const result=patchLocalPhoneConfig(config);
 console.log('CHECK isolated phone provider: owned temporary config only; phone password feature enabled; SMS confirmations and Twilio transport disabled, credentials absent, OTP routes refused.');
 return result;
}
