// Emits one bounded READ ONLY catalog query. Never connects to a DB.
import fs from 'node:fs/promises';
import path from 'node:path';
import {catalogSql,newSchemas} from './prepare_atomic_review.mjs';
export async function preflightQuery(root){
 const source=await fs.readFile(path.join(root,'docs/review/site-order-private-baseline/existing_catalog_normalized.sql'),'utf8');
 return preflightStatement(source);
}
export function preflightStatement(source){
 const query=catalogSql(source,['auth','private','public']);
 const schemas=newSchemas.map(n=>"'"+n+"'").join(',');
 return `begin read only;set local search_path='';select jsonb_build_object('kind','native-production-readonly-normalized-v1','production_mutation',false,'server_version_num',current_setting('server_version_num'),'captured_at',transaction_timestamp(),'snapshot',(select v from (${query}) q),'new_namespace_presence',(select jsonb_object_agg(n,to_regnamespace(n)is not null order by n)from unnest(array[${schemas}]::text[])n)) v;commit;\n`;
}
if(process.argv[1]===new URL(import.meta.url).pathname){if(!process.argv[2])throw Error('absolute repository root required');process.stdout.write(await preflightQuery(path.resolve(process.argv[2])));}
