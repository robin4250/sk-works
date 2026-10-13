export function validateIncomeViewerFixtureUrl(value){
 const reject=()=>{throw new Error('Only the local disposable income-viewer fixture URL is permitted');};let url;try{url=new URL(value);}catch{reject();}
 if(!['postgres:','postgresql:'].includes(url.protocol)||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/sko_company_income_viewer_fixture'||url.port!=='5432'||url.search||url.hash||url.username!=='postgres'||url.password!=='fixture-only-password')reject();return url.href;
}
