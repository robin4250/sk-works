"""Official npm distributions, exact version and registry integrity, no scripts."""
import json,pathlib,subprocess,os
p=pathlib.Path(__file__).resolve().parent
for version,pin in json.loads((p/'runtime-pins.json').read_text()).items():
 target=p/'build'/('deno146' if version=='1.46.3' else 'deno')
 subprocess.run(['npm','install','--prefix',str(target),'--ignore-scripts','--save-exact','@deno/linux-x64-glibc@'+version],check=True)
 lock=json.loads((target/'package-lock.json').read_text())['packages']['node_modules/@deno/linux-x64-glibc']
 assert all(lock[k]==pin[k] for k in ['version','resolved','integrity'])
 exe=target/'node_modules/@deno/linux-x64-glibc/deno';exe.chmod(exe.stat().st_mode|0o100)
 subprocess.run([str(exe),'--version'],check=True)
