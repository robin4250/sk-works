import {createRequire} from 'node:module';
import {checkOwnerIssuerStore} from './owner-issuer-store.check.mjs';
const require=createRequire(process.cwd()+'/tool/security/fixture_dependencies/package.json');
const {Pool}=require('pg'),pool=new Pool({max:5});
try{await checkOwnerIssuerStore({pool,nativeConcurrency:true});}finally{await pool.end();}
