import module from './decoy.wasm';
import {binaryHex,binarySha256,constantBody} from './wasm-manifest.mjs';
let checked;
async function initialize(){
 const bytes=Uint8Array.from(binaryHex.match(/../g),x=>parseInt(x,16));
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join('');
 if(hash!==binarySha256||WebAssembly.Module.imports(module).length!==0)throw Error('Wasm boundary differs');
 const exports=WebAssembly.Module.exports(module).map(x=>[x.name,x.kind]);
 if(JSON.stringify(exports)!==JSON.stringify([['memory','memory'],['status','function'],['response_ptr','function'],['response_len','function']]))throw Error('Wasm exports differ');
 const instance=new WebAssembly.Instance(module,{}),e=instance.exports;
 if(e.memory.buffer.byteLength!==65536)throw Error('Wasm memory differs');
 let refused=false;try{e.memory.grow(1);}catch{refused=true;}if(!refused)throw Error('Wasm maximum memory differs');
 return e;
}
export async function renderDecoy(){
 const e=await(checked??=initialize()),ptr=e.response_ptr(),len=e.response_len();
 if(e.status()!==200||ptr!==0||len!==constantBody.length||e.memory.buffer.byteLength!==65536)throw Error('Wasm response differs');
 const body=new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(e.memory.buffer,ptr,len));
 if(body!==constantBody)throw Error('Wasm data differs');return body;
}
