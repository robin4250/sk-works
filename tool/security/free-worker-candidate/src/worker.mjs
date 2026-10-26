export {DecoyBroker} from './broker.mjs';
export async function publicFetch(request,env){
 const url=new URL(request.url);
 if(request.body)void request.body.cancel().catch(()=>{});
 if(!env.DECOY_HOST||url.hostname!==env.DECOY_HOST||url.search||url.pathname.length>256||request.method!=='GET')return new Response(null,{status:404});
 let target,generation;
 if(url.pathname==='/synthetic-decoy/capability')target='/capability';
 else{const m=/^\/synthetic-decoy\/g([1-9][0-9]{0,5})\/fixture-records$/.exec(url.pathname);if(!m)return new Response(null,{status:404});target='/observe';generation=m[1];}
 const headers=new Headers();
 if(generation){headers.set('x-sko-decoy-generation',generation);const token=request.headers.get('x-sko-decoy-capability');if(token&&token.length<=512)headers.set('x-sko-decoy-capability',token);}
 // Public headers cannot supply identity, company, key, policy or outbound origin.
 return env.DECOY.get(env.DECOY.idFromName('security-decoy-v1')).fetch(new Request('https://internal.invalid'+target,{headers}));
}
export default {fetch:publicFetch};
