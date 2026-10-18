// This URL is only a disposable CI service, never a project database.
export function validateWorkerDocumentFixtureUrl(value) {
 const reject=()=>{throw Error('Only local disposable sko_document_change_fixture is permitted');};
 let url;try{url=new URL(value);}catch{reject();}
 if(!['postgres:','postgresql:'].includes(url.protocol)||!['127.0.0.1','localhost'].includes(url.hostname)||url.port!=='5432'||url.pathname!=='/sko_document_change_fixture'||url.search||url.hash||url.username!=='postgres'||url.password!=='fixture-only')reject();
 return url.href;
}
