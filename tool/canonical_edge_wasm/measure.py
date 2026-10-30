"""Actual official Deno child rusage, no network/DB/deploy or runtime substitute."""
import pathlib,subprocess,time,resource,os,json,hashlib
P=pathlib.Path(__file__).resolve().parent
root=P.parents[2]
runtimes={'2.9.6':P/'build/deno/node_modules/@deno/linux-x64-glibc/deno','1.46.3':P/'build/deno146/node_modules/@deno/linux-x64-glibc/deno'}
results=[]
for version,exe in runtimes.items():
 for name in ['order-v1','order-v2','acceptance-v1','acceptance-v2']:
  stdout=P/f'build/cold-{version}-{name}.json';stderr=P/f'build/cold-{version}-{name}.stderr'
  cmd=[str(exe),'run','--no-remote','--allow-read='+str(P/'build'),'--allow-write='+str(P/'build/out'),str(P/'run_deno.mjs'),name]
  start=time.perf_counter()
  with stdout.open('wb') as out,stderr.open('wb') as err:
   child=subprocess.Popen(cmd,cwd=root,stdout=out,stderr=err)
   pid,status,usage=os.wait4(child.pid,0);child.returncode=os.waitstatus_to_exitcode(status)
  result={'version':version,'case':name,'exit':child.returncode,'wall_s':time.perf_counter()-start,'user_cpu_s':usage.ru_utime,'system_cpu_s':usage.ru_stime,'total_cpu_s':usage.ru_utime+usage.ru_stime,'peak_rss_bytes':usage.ru_maxrss*1024,'binary_sha256':hashlib.sha256(exe.read_bytes()).hexdigest()}
  if child.returncode==0:result['deno']=json.loads(stdout.read_text())
  else:result['error']=stderr.read_text()[:300]
  results.append(result);print(json.dumps({k:v for k,v in result.items() if k not in ['deno','binary_sha256']}),flush=True)
(P/'build/cold-measurements.json').write_text(json.dumps(results,indent=2)+'\n')

assert all(r['exit']==0 for r in results), 'actual Deno process failed'
