import pathlib,hashlib,json
root=pathlib.Path(__file__).resolve().parents[1]/'src';body=b'{"environment":"synthetic-only","records":[]}'
def u(n):
 out=[]
 while True:
  b=n&127;n>>=7;out.append(b|(128 if n else 0))
  if not n:return bytes(out)
def sec(i,b):return bytes([i])+u(len(b))+b
def text(s):b=s.encode();return u(len(b))+b
funcs=[200,0,len(body)]
mod=b'\0asm\1\0\0\0'+sec(1,b'\1\x60\0\1\x7f')+sec(3,b'\3\0\0\0')+sec(5,b'\1\1\1\1')
exports=[('memory',2,0),('status',0,0),('response_ptr',0,1),('response_len',0,2)]
mod+=sec(7,u(len(exports))+b''.join(text(n)+bytes([t])+u(idx) for n,t,idx in exports))
code=[]
for n in funcs:
 # positive signed LEB128; append 0 if final sign bit would be set
 leb=bytearray(u(n))
 if leb[-1]&64:leb[-1]|=128;leb.append(0)
 b=b'\0\x41'+bytes(leb)+b'\x0b';code.append(u(len(b))+b)
mod+=sec(10,u(len(code))+b''.join(code))+sec(11,b'\1\0\x41\0\x0b'+u(len(body))+body)
(root/'decoy.wasm').write_bytes(mod)
(root/'wasm-manifest.mjs').write_text('export const binaryHex='+json.dumps(mod.hex())+';\nexport const binarySha256='+json.dumps(hashlib.sha256(mod).hexdigest())+';\nexport const constantBody='+json.dumps(body.decode())+';\n')
(root/'decoy.wat').write_text('(module\n (memory (export "memory") 1 1)\n (func (export "status") (result i32) i32.const 200)\n (func (export "response_ptr") (result i32) i32.const 0)\n (func (export "response_len") (result i32) i32.const '+str(len(body))+')\n (data (i32.const 0) "'+body.decode().replace('"','\\22')+'")\n)\n')
print(json.dumps({'bytes':len(mod),'sha256':hashlib.sha256(mod).hexdigest(),'imports':0,'memory_initial_pages':1,'memory_maximum_pages':1}))
