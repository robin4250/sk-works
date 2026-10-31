import fs from 'node:fs/promises';
import {rmSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const source=await fs.readFile(new URL('./verify_site_order_outgoing_observation.mjs',import.meta.url),'utf8');
const anchor="['site_order_outgoing_observation_fixture','verifyOutgoingObservation']]";
if(source.split(anchor).length!==2)throw Error('outgoing observation hook changed');
const temp=fileURLToPath(new URL(`./.outgoing-targets-${randomUUID()}.mjs`,import.meta.url));
try {
 await fs.writeFile(temp,source.replace(anchor,"['site_order_outgoing_observation_fixture','verifyOutgoingObservation'],['site_order_prepare_operation_fixture','verifyPrepareOperations'],['site_order_registered_targets_fixture','verifyRegisteredTargets']]"),{mode:0o600,flag:'wx'});
 const result=spawnSync(process.execPath,[temp,...process.argv.slice(2)],{env:process.env,stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)throw Error('registered targets fixture failed: '+(result.status??result.signal));
} finally {rmSync(temp,{force:true});}
