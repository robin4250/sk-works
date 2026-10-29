import {checkOwnerIssuerStore} from './owner-issuer-store.check.mjs';
const path=process.env.SKO_TEST_PGLITE_MODULE??new URL('../fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js',import.meta.url).href;
const {PGlite}=await import(path),db=new PGlite();
const client={query:async(sql,args)=>args?db.query(sql,args):((await db.exec(sql)).at(-1)??{rows:[]}),release:()=>{}};
const pool={query:client.query,connect:async()=>client};
try{await checkOwnerIssuerStore({pool,pglite:true});}finally{await db.close();}
