// Minimal server-only REST adapter. No credentials/provider bodies in errors.
export function createDeletionServiceClient({origin,serviceKey,fetchImpl=fetch}){
 const base=new URL(origin);
 if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash||!serviceKey)throw Error('service_client_not_configured');
 const request=async(method,path,body,existenceOnly=false)=>{
  try{
   const r=await fetchImpl(base.origin+path,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
   if(existenceOnly&&r.ok){await r.body?.cancel();return {status:r.status,ok:true,data:null};}
   let data=null;try{data=await r.json();}catch{}
   return {status:r.status,ok:r.ok,data};
  }catch{return {status:0,ok:false,data:null};}
 };
 const failure=r=>({error:{status:r.status,code:r.data?.code==='user_not_found'||r.data?.error_code==='user_not_found'?'user_not_found':'service_unavailable'}});
 const objectPath=(b,p)=>encodeURIComponent(b)+'/'+p.split('/').map(encodeURIComponent).join('/');
 return {
  rpc:async(name,args)=>{if(!/^[a-z_]+$/.test(name))return failure({status:0});const r=await request('POST','/rest/v1/rpc/'+name,args);return r.ok?{data:r.data,error:null}:failure(r);},
  auth:{admin:{
   getUserById:async id=>{const r=await request('GET','/auth/v1/admin/users/'+encodeURIComponent(id));return r.ok?{data:{user:r.data},error:null}:failure(r);},
   updateUserById:async(id,attrs)=>{const r=await request('PUT','/auth/v1/admin/users/'+encodeURIComponent(id),attrs);return r.ok?{data:{user:r.data},error:null}:failure(r);},
   deleteUser:async id=>{const r=await request('DELETE','/auth/v1/admin/users/'+encodeURIComponent(id));return r.ok?{error:null}:failure(r);},
  }},
  storage:{from:bucket=>({
   exists:async path=>{
    const r=await request('GET','/storage/v1/object/authenticated/'+objectPath(bucket,path),undefined,true);
    if(r.ok)return {data:true,error:null};
    if([400,404].includes(r.status)&&String(r.data?.statusCode)==='404'&&r.data?.message==='Object not found')return {data:false,error:null};
    return failure(r);
   },
   createSignedUrl:async(path,expiresIn)=>{
    const r=await request('POST','/storage/v1/object/sign/'+objectPath(bucket,path),{expiresIn});
    if(!r.ok||typeof r.data?.signedURL!=='string')return failure(r);
    const signedUrl=base.origin+'/storage/v1'+r.data.signedURL;
    if(!r.data.signedURL.startsWith('/object/sign/')||new URL(signedUrl).origin!==base.origin)return failure({status:0});
    return {data:{signedUrl},error:null};
   },
   remove:async paths=>{const r=await request('DELETE','/storage/v1/object/'+encodeURIComponent(bucket),{prefixes:paths});return r.ok?{data:r.data,error:null}:failure(r);},
  })},
 };
}
