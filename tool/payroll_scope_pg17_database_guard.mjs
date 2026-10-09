export function validatePayrollScopeFixtureUrl(value) {
 const reject=()=>{throw new Error('Only the local disposable payroll-scope fixture URL is permitted');};
 let url;try{url=new URL(value);}catch{reject();}
 if(!['postgres:','postgresql:'].includes(url.protocol)||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/sko_payroll_scope_fixture'||url.port!=='5432'||url.search||url.hash||url.username!=='postgres'||url.password!=='fixture-only-password')reject();
 return url.href;
}
