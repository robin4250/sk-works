// Keep the canonical and site-history harnesses unchanged; only a private copy
// receives this next review hook.
import fs from 'node:fs/promises';
import {rmSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const original=new URL('./verify_site_order_site_history.mjs',import.meta.url);
const source=await fs.readFile(original,'utf8');
const anchor="['site_order_site_history_fixture','verifySiteOrderSiteHistory']]";
if(source.split(anchor).length!==2)throw Error('site-history hook changed');
const temp=fileURLToPath(new URL(`./.outgoing-observation-${randomUUID()}.mjs`,import.meta.url));
try{
 await fs.writeFile(temp,source.replace(anchor,"['site_order_site_history_fixture','verifySiteOrderSiteHistory'],['site_order_outgoing_observation_fixture','verifyOutgoingObservation']]"),{mode:0o600,flag:'wx'});
 const result=spawnSync(process.execPath,[temp,...process.argv.slice(2)],{env:process.env,stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)throw Error('outgoing observation fixture failed: '+(result.status??result.signal));
}finally{rmSync(temp,{force:true});}
