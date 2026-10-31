// Separate bounded purpose. Legacy workflow requests retain their 4096-byte cap.
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const identity=['site_id','document_id','local_id','trade_id','request_id'];
const commands={
 targets:{keys:['site_id','before','limit'],sql:'select site_order_outgoing_private.registered_targets($1,$2,$3) as result'},
 prepare:{keys:[...identity,'connection_fingerprint','body'],sql:'select site_order_outgoing_private.prepare_order($1,$2,$3,$4,$5,$6,$7::jsonb) as result'},
 status:{keys:identity,sql:'select site_order_outgoing_private.operation_status($1,$2,$3,$4,$5) as result'},
 retire:{keys:[...identity,'confirmed'],sql:'select site_order_outgoing_private.retire_prepare($1,$2,$3,$4,$5,$6) as result'},
};
const response=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
async function read(req){
 const reader=req.body?.getReader();if(!reader)throw Error('invalid_request');
 const chunks=[];let size=0;
 for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;
  if(size>65_536){await reader.cancel();throw Error('invalid_request');}chunks.push(value);}
 const bytes=new Uint8Array(size);let offset=0;
 for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('invalid_request');
 if(value.action!=='prepare'&&size>4096)throw Error('invalid_request');
 const command=commands[value.action];
 if(!command||Object.keys(value).length!==command.keys.length+1
  ||Object.keys(value).some(key=>key!=='action'&&!command.keys.includes(key)))throw Error('invalid_request');
 for(const key of command.keys){const item=value[key];
  if(key==='before'){
   if(item!==null&&(typeof item!=='string'||!uuid.test(item)))throw Error('invalid_request');
  }else if(key==='limit'){
   if(!Number.isInteger(item)||item<1||item>50)throw Error('invalid_request');
  }else if(key==='body'){
   if(!item||typeof item!=='object'||Array.isArray(item)
    ||new TextEncoder().encode(JSON.stringify(item)).length>32768)throw Error('invalid_request');
  }else if(key==='connection_fingerprint'){
   if(typeof item!=='string'||!/^[0-9a-f]{64}$/.test(item))throw Error('invalid_request');
  }else if(key==='confirmed'){
   if(item!==true)throw Error('invalid_request');
  }else if(typeof item!=='string'||!uuid.test(item))throw Error('invalid_request');
 }
 return {value,command};
}
// The runtime injects its existing pinned project verifier and dedicated TLS
// connection factory. HTTP cannot select authentication, SQL or connection data.
export function createOutgoingPrepareHandler({verify,connect}){
 return async req=>{
  if(req.method!=='POST')return response({error:'post_required'},405);
  const authorization=req.headers.get('authorization')??'';
  if(authorization.length>16_384||!/^Bearer [^\s]+$/.test(authorization))return response({error:'authentication_required'},401);
  let claims;try{claims=await verify(authorization.slice(7));}catch{return response({error:'authentication_required'},401);}
  let input;try{input=await read(req);}catch{return response({error:'invalid_request'},400);}
  let db,commitStarted=false;
  try{
   db=await connect();await db.query('begin isolation level read committed');
   if((await db.query('select session_user as role')).rows[0]?.role!=='postgres')throw Error('internal_connection_required');
   await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(claims)]);
   const args=input.command.keys.map(key=>key==='body'?JSON.stringify(input.value[key]):input.value[key]);
   const result=(await db.query(input.command.sql,args)).rows[0]?.result;
   if(!result||typeof result!=='object'||Array.isArray(result))throw Error('result_required');
   commitStarted=true;await db.query('commit');commitStarted=false;
   return response({result});
  }catch{
   if(db&&!commitStarted)await db.query('rollback').catch(()=>{});
   return response({error:commitStarted?'result_unknown':'operation_rejected',retry_automatically:false},commitStarted?409:403);
  }finally{if(db)await db.end().catch(()=>{});}
 };
}
